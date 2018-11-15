defmodule Potoo.Channel do
  use GenServer

  require Logger
  require OK

  defmacro is_channel(value) do
    quote do
      (
        is_tuple(unquote(value)) and
        tuple_size(unquote(value)) == 2 and
        elem(unquote(value), 0) == Potoo.Channel and
        is_pid(elem(unquote(value), 1))
      )
    end
  end

  def start(opts \\ []) do
    case GenServer.start(__MODULE__, initial_state(opts), opts) do
      {:ok, pid} -> {:ok, {__MODULE__, pid}}
      err        -> err
    end
  end

  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, initial_state(opts), opts) do
      {:ok, pid} -> {:ok, {__MODULE__, pid}}
      err        -> err
    end
  end

  def start_link!(opts \\ []) do
    {:ok, chan} = start_link(opts)
    chan
  end

  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  def map(chan = {__MODULE__, _}, fun, opts \\ []) do
    OK.for do
      mapped_chan <- start_link([{:transform, fun} | opts])
      {__MODULE__, mapped_pid} = mapped_chan
    after
      case subscribe(chan, mapped_pid, :send) do
        :ok -> mapped_chan
        err -> err
      end
    end
  end

  def map!(chan, fun, opts \\ []) do
    {:ok, mapped_chan} = map(chan, fun, opts)
    mapped_chan
  end

  def subscribe({__MODULE__, channel}, pid, token) do
    GenServer.call(channel, {:subscribe, pid, token})
  end

  def unsubscribe({__MODULE__, channel}, pid) do
    GenServer.cast(channel, {:unsubscribe, pid})
  end

  def unsubscribe({__MODULE__, channel}, pid, token) do
    GenServer.cast(channel, {:unsubscribe, pid, token})
  end

  def send({__MODULE__, channel}, message) do
    GenServer.cast(channel, {:send, message})
  end

  def send_lazy({__MODULE__, channel}, fun) do
    GenServer.cast(channel, {:send_lazy, fun})
  end

  def pid({__MODULE__, pid}), do: pid

  def last_message({__MODULE__, channel}) do
    GenServer.call(channel, :last_message)
  end

  def handle_call({:subscribe, pid, token}, _from, state = %{subscribers: subscribers}) do
    Logger.debug fn ->
      "subscribing pid #{inspect(pid)} to channel #{inspect(self())}"
    end

    Process.monitor(pid)

    new_subscribers = Map.update(
      subscribers, pid, MapSet.new([token]),
      fn(tokens) -> MapSet.put(tokens, token) end
    )

    {:reply, :ok, %{ state | subscribers: new_subscribers }}
  end

  def handle_call(:last_message, _from, state = %{last_message: last_message}) do
    {:reply, last_message, state}
  end

  def handle_call(:last_message, _from, state = %{retain: false}) do
    {:reply, nil, state}
  end

  def handle_call(:last_message, _from, state = %{default: default}) do
    {:reply, default, state}
  end

  def handle_cast({:send, message}, state = %{subscribers: subscribers, retain: false}) do
    dispatch(subscribers, message)

    {:noreply, state}
  end

  def handle_cast({:send, message}, state = %{subscribers: subscribers, retain: true}) do
    dispatch(subscribers, message)

    {:noreply, Map.put(state, :last_message, message)}
  end

  def handle_cast({:send, message}, state = %{subscribers: subscribers, retain: :deduplicate, last_message: last_message}) do
    if message != last_message do
      dispatch(subscribers, message)
    end

    {:noreply, %{state | last_message: message}}
  end

  def handle_cast({:send, message}, state = %{subscribers: subscribers, retain: :deduplicate}) do
    dispatch(subscribers, message)

    {:noreply, Map.put(state, :last_message, message)}
  end

  def handle_cast({:send_lazy, fun}, state = %{subscribers: subscribers}) do
    case subscribers == %{} do
      true -> {:noreply, state}
      false -> handle_cast({:send, fun.()}, state)
    end
  end

  def handle_cast({:unsubscribe, pid}, state = %{subscribers: subscribers}) do
    Logger.debug fn ->
      "unsubscribing pid #{inspect(pid)} from channel #{inspect(self())}"
    end
    {:noreply, %{ state | subscribers: Map.delete(subscribers, pid)} }
  end

  def handle_cast({:unsubscribe, pid, token}, state = %{subscribers: subscribers}) do
    Logger.debug fn ->
      "unsubscribing pid #{inspect(pid)} from channel #{inspect(self())} with token #{inspect(token)}"
    end

    tokens = Map.get(subscribers, pid, MapSet.new())
      |> MapSet.delete(token)

    new_subscribers = case MapSet.size(tokens) do
      0 -> Map.delete(subscribers, pid)
      _ -> Map.put(subscribers, pid, tokens)
    end

    {:noreply, %{ state | subscribers: new_subscribers} }
  end

  def handle_info({:send, message}, state) do
    handle_cast({:send, message}, state)
  end

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    handle_cast({:unsubscribe, pid}, state)
  end

  def handle_info({:EXIT, _, _}, state) do
    {:stop, {:shutdown, :link_exited}, state}
  end

  defp dispatch(subscribers, message) do
    subscribers |> Enum.map(fn(target) -> dispatch_single(target, message) end)
  end

  defp dispatch_single({pid, tokens}, message) do
    tokens |> Enum.map(fn(token) ->
      Kernel.send(pid, {token, message})
    end)
  end

  defp initial_state(opts) do
    opts_map = Map.new(opts)
    %{
      subscribers: %{},
      transform: Map.get(opts_map, :transform),
      default: Map.get(opts_map, :default),
      retain: Map.get(opts_map, :retain, false),
    }
  end
end