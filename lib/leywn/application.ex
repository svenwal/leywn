defmodule Leywn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    _ = Leywn.Logos.ensure()
    Application.put_env(:leywn, :jwt_signing_key, :crypto.strong_rand_bytes(32))
    Application.put_env(:leywn, :started_at, System.monotonic_time(:second))

    port = Application.get_env(:leywn, :port, 4000)
    tls_port = Application.get_env(:leywn, :tls_port, 4443)
    tls_opts = Leywn.MTLS.init()

    max_connections = 1_000

    children = [
      {Plug.Cowboy, scheme: :http,  plug: Leywn.Router,
        options: [port: port,     transport_options: [max_connections: max_connections]]},
      {Plug.Cowboy, scheme: :https, plug: Leywn.Router,
        options: [port: tls_port, transport_options: [max_connections: max_connections]] ++ tls_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Leywn.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
