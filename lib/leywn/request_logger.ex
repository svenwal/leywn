defmodule Leywn.RequestLogger do
  @moduledoc """
  A plug that logs every request to stdout as a single structured line:

      2026-04-08T12:00:00Z GET /echo remote=127.0.0.1 status=200 duration=3ms
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      duration_ms =
        System.monotonic_time()
        |> Kernel.-(start)
        |> System.convert_time_unit(:native, :millisecond)

      remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()
      ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      IO.puts("#{ts} #{conn.method} #{conn.request_path} remote=#{remote_ip} status=#{conn.status} duration=#{duration_ms}ms")
      conn
    end)
  end
end
