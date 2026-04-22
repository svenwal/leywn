defmodule Leywn.ChaosTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  @opts Leywn.Router.init([])

  defp call(method, path, headers \\ []) do
    conn(method, path)
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> Leywn.Router.call(@opts)
  end

  # ---- defaults (no fault) ---------------------------------------------------

  test "/chaos-engineering with 0/0/0/0 always returns 200 echo" do
    conn = call(:get, "/chaos-engineering/0/0/0/0")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert Map.has_key?(body, "_chaos")
    assert body["_chaos"]["error_injected"] == false
    assert body["_chaos"]["mangled"] == false
    assert body["_chaos"]["latency_applied_ms"] == 0
    assert Map.has_key?(body, "method")
  end

  # ---- always-error ----------------------------------------------------------

  test "/chaos-engineering/100/0/0/0 always returns an error status" do
    conn = call(:get, "/chaos-engineering/100/0/0/0")
    assert conn.status in [400, 401, 403, 404, 408, 409, 422, 429, 500, 502, 503, 504]
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "chaos_error_injected"
    assert body["_chaos"]["error_injected"] == true
  end

  # ---- always-mangled --------------------------------------------------------

  test "/chaos-engineering/0/100/0/0 returns a mangled (invalid JSON) body" do
    conn = call(:get, "/chaos-engineering/0/100/0/0")
    assert conn.status == 200
    assert match?({:error, %Jason.DecodeError{}}, Jason.decode(conn.resp_body))
    assert conn.resp_body =~ "!!MANGLED"
  end

  # ---- path params -----------------------------------------------------------

  test "/chaos-engineering path params appear in _chaos meta" do
    conn = call(:get, "/chaos-engineering/5/15/25/1000")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["_chaos"]["error_percentage"] == 5
    assert body["_chaos"]["mangled_percentage"] == 15
    assert body["_chaos"]["latency_percentage"] == 25
    assert body["_chaos"]["maximum_latency_ms"] == 1000
  end

  # ---- header params ---------------------------------------------------------

  test "/chaos-engineering X-Chaos-* headers override defaults" do
    conn =
      call(:get, "/chaos-engineering", [
        {"x-chaos-error-percentage", "0"},
        {"x-chaos-mangled-percentage", "0"},
        {"x-chaos-latency-percentage", "0"},
        {"x-chaos-maximum-latency", "500"}
      ])

    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["_chaos"]["error_percentage"] == 0
    assert body["_chaos"]["mangled_percentage"] == 0
    assert body["_chaos"]["latency_percentage"] == 0
    assert body["_chaos"]["maximum_latency_ms"] == 500
  end

  # ---- validation ------------------------------------------------------------

  test "/chaos-engineering returns 400 for percentage > 100" do
    conn = call(:get, "/chaos-engineering/101/0/0/0")
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "invalid_chaos_params"
  end

  test "/chaos-engineering returns 400 for maximum_latency > 30000" do
    conn = call(:get, "/chaos-engineering/0/0/0/99999")
    assert conn.status == 400
  end

  test "/chaos-engineering returns 400 for non-integer params" do
    conn = call(:get, "/chaos-engineering/abc/0/0/0")
    assert conn.status == 400
  end

  test "/chaos-engineering returns 400 for negative percentage" do
    conn = call(:get, "/chaos-engineering/-1/0/0/0")
    assert conn.status == 400
  end

  # ---- echo data present -----------------------------------------------------

  test "/chaos-engineering includes echo fields in happy-path response" do
    conn = call(:post, "/chaos-engineering/0/0/0/0")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["method"] == "POST"
    assert Map.has_key?(body, "headers")
    assert Map.has_key?(body, "path")
  end
end
