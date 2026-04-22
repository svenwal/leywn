defmodule Leywn.CORS do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = System.get_env("LEYWN_CORS_ORIGIN") || "*"

    conn =
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "*")
      |> put_resp_header("access-control-max-age", "86400")

    if conn.method == "OPTIONS" do
      conn
      |> send_resp(204, "")
      |> halt()
    else
      conn
    end
  end
end
