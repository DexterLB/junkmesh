defmodule GlobalRegistry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Supervisor.Spec

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: GlobalRegistry.Worker.start_link(arg)
      # {GlobalRegistry.Worker, arg},
      worker(
        Mesh.Registry,
        [
          %{
            "description" => "The global registry"
          },
          [name: :global_registry]
        ]
      ),
      unless Application.get_env(:global_registry, :no_toys, false) do
        worker(GlobalRegistry.Hello, [:global_registry, [name: GlobalRegistry.Hello]])
      end,
      unless Application.get_env(:global_registry, :no_toys, false) do
        worker(GlobalRegistry.Clock, [:global_registry, [name: GlobalRegistry.Clock]])
      end
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_all, name: GlobalRegistry.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
