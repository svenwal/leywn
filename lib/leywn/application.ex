defmodule Leywn.Application do
  @moduledoc false

  use Application

  @leywn_vars [
    "LEYWN_PORT",
    "LEYWN_TLS_PORT",
    "LEYWN_ECHO_MAX_BODY_BYTES",
    "LEYWN_ECHO_ON_HOME",
    "LEYWN_ONLY_JSON",
    "LEYWN_CORS_ORIGIN",
    "LEYWN_TRUST_FORWARD",
    "LEYWN_EXTERNAL_HTTP_URL",
    "LEYWN_EXTERNAL_HTTPS_URL",
    "LEYWN_NAMES_FILE",
    "LEYWN_EMAIL_DOMAINS_FILE",
    "LEYWN_TLS_SERVER_KEY",
    "LEYWN_TLS_SERVER_CRT",
    "LEYWN_MTLS_CERT",
    "LEYWN_MTLS_KEY",
    "LEYWN_MTLS_IN_HEADER"
  ]

  # Values for these vars are PEM blobs — show presence only, never the content.
  @sensitive_vars ~w(LEYWN_TLS_SERVER_KEY LEYWN_TLS_SERVER_CRT LEYWN_MTLS_CERT LEYWN_MTLS_KEY)

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
      {Plug.Cowboy,
       scheme: :http,
       plug: Leywn.Router,
       options: [port: port, transport_options: [max_connections: max_connections]]},
      {Plug.Cowboy,
       scheme: :https,
       plug: Leywn.Router,
       options:
         [port: tls_port, transport_options: [max_connections: max_connections]] ++ tls_opts}
    ]

    opts = [strategy: :one_for_one, name: Leywn.Supervisor]
    result = Supervisor.start_link(children, opts)
    if match?({:ok, _}, result), do: print_banner(port, tls_port)
    result
  end

  defp print_banner(port, tls_port) do
    version = Application.spec(:leywn, :vsn) |> to_string()

    IO.puts(
      "Leywn version #{version} has been started, listening on ports #{port} (HTTP) and #{tls_port} (HTTPS/mTLS)."
    )

    set_vars =
      @leywn_vars
      |> Enum.filter(&(System.get_env(&1) not in [nil, ""]))
      |> Enum.map(fn var ->
        value = if var in @sensitive_vars, do: "<set>", else: System.get_env(var)
        "  - #{var}: #{value}"
      end)

    if set_vars == [] do
      IO.puts("No LEYWN_* environment variables have been set (using defaults).")
    else
      IO.puts("The following environment variables have been set:")
      Enum.each(set_vars, &IO.puts/1)
    end
  end
end
