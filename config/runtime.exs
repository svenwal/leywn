import Config

defmodule Leywn.RuntimeConfig do
  def int_env(var, default) when is_integer(default) do
    case System.get_env(var) do
      nil -> default
      "" -> default
      value ->
        case Integer.parse(value) do
          {n, ""} -> n
          _ -> default
        end
    end
  end
end

config :leywn,
  port: Leywn.RuntimeConfig.int_env("LEYWN_PORT", 4000),
  tls_port: Leywn.RuntimeConfig.int_env("LEYWN_TLS_PORT", 4443),
  echo_max_body_bytes: Leywn.RuntimeConfig.int_env("LEYWN_ECHO_MAX_BODY_BYTES", 65_536)

