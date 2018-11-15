defmodule PotooServer.Api do

  alias Potoo.ServerUtils.PidCache
  alias Potoo.Contract.Delegate
  alias Potoo.Cache

  require Logger
  require OK

  def call(%{"target" => target = %Delegate{}, "path" => path, "argument" => argument}) do
    Cache.call(Cache, target, String.split(path, "/"), argument, true)
      |> check_fail
  end

  def call(%{"path" => _, "argument" => _} = handle) do
    call(Map.put(handle, "target",
      %Delegate{
        destination: PidCache.get(PidCache, {:delegate, 0})
      }
    ))
  end

  def subscribe(%{"channel" => chan = {Potoo.Channel, _}, "token" => token}) do
    chan
      |> Potoo.Channel.subscribe(self(), {:subscription, token})
  end

  def unsubscribe(%{"channel" => chan = {Potoo.Channel, _}, "token" => token}) do
    chan
      |> Potoo.Channel.unsubscribe(self(), {:subscription, token})
  end

  def unsafe_call(%{"target" => target = %Delegate{}, "function_name" => name, "argument" => argument}) do
    target
      |> Potoo.unsafe_call(name, argument)
  end

  def get_contract(%{"target" => target = %Delegate{}}) do
    Cache.get_contract(Cache, target)
  end

  def subscribe_contract(%{"target" => target = %Delegate{}}) do
    Cache.subscribe_contract(Cache, target)
  end

  def get_and_subscribe_contract(%{"target" => target = %Delegate{}, "token" => token}) do
    contract = Cache.get_contract(Cache, target)

    case Cache.subscribe_contract(Cache, target) do
      {Potoo.Channel, _} = channel ->
        :ok = Potoo.Channel.subscribe(channel, self(), {:subscription, token})

        contract

      err -> err
    end
  end

  def my_pid(endpoint) do
    %Delegate{
      destination: endpoint
    }
  end

  def make_channel() do
    {:ok, chan} = Potoo.Channel.start_link()
    chan
  end

  def send_on(channel = {Potoo.Channel, _}, message) do
    Potoo.Channel.send(channel, message)
  end


  defp check_fail({:error, err}) do
    %{"error" => err}
  end
  defp check_fail({:ok, x}), do: x
  defp check_fail(x), do: x
end