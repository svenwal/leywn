defmodule Leywn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    _ = Leywn.Logos.ensure()

    port = Application.get_env(:leywn, :port, 4000)
    tls_port = Application.get_env(:leywn, :tls_port, 4443)
    tls_opts = Leywn.MTLS.init()

    children = [
      {Plug.Cowboy, scheme: :http, plug: Leywn.Router, options: [port: port]},
      {Plug.Cowboy, scheme: :https, plug: Leywn.Router, options: [port: tls_port] ++ tls_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Leywn.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
