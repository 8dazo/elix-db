defmodule ElixDb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:elix_db, :http_port, 4000)
    children = [
      ElixDb.Metrics,
      {ElixDb.CollectionRegistry, [store: ElixDb.Store]},
      {ElixDb.Store, [registry: ElixDb.CollectionRegistry]},
      {Plug.Cowboy, scheme: :http, plug: ElixDb.HttpRouter, options: [port: port]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ElixDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
