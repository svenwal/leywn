defmodule Leywn.ChaosTest do
  use ExUnit.Case, async: true
  import Plug.Test

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
    # 0/0/0 for error/mangled/latency guarantees a deterministic 200 with no sleep;
    # non-zero max_latency confirms the value is still reflected in the meta.
    conn = call(:get, "/chaos-engineering/0/0/0/500")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["_chaos"]["error_percentage"] == 0
    assert body["_chaos"]["mangled_percentage"] == 0
    assert body["_chaos"]["latency_percentage"] == 0
    assert body["_chaos"]["maximum_latency_ms"] == 500
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

  # ---- header validation -----------------------------------------------------
  # The X-Chaos-* headers are validated against the same ranges as the path
  # variant. Without that, X-Chaos-Maximum-Latency could hold a connection open
  # for as long as the caller asked — a trivial denial of service.

  test "/chaos-engineering rejects a maximum latency above 30 000 ms" do
    conn = call(:get, "/chaos-engineering", [{"x-chaos-maximum-latency", "600000"}])
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "invalid_chaos_params"
    assert body["field"] == "x-chaos-maximum-latency"
  end

  test "/chaos-engineering returns quickly when an oversized latency is rejected" do
    t0 = System.monotonic_time(:millisecond)
    conn = call(:get, "/chaos-engineering", [{"x-chaos-maximum-latency", "600000"}])
    elapsed = System.monotonic_time(:millisecond) - t0

    assert conn.status == 400
    assert elapsed < 1_000, "request slept for #{elapsed}ms instead of being rejected"
  end

  test "/chaos-engineering rejects a negative maximum latency" do
    conn = call(:get, "/chaos-engineering", [{"x-chaos-maximum-latency", "-1"}])
    assert conn.status == 400
  end

  test "/chaos-engineering rejects out-of-range percentages in headers" do
    for header <- ~w(x-chaos-error-percentage x-chaos-mangled-percentage
                     x-chaos-latency-percentage) do
      assert call(:get, "/chaos-engineering", [{header, "101"}]).status == 400
      assert call(:get, "/chaos-engineering", [{header, "-1"}]).status == 400
    end
  end

  test "/chaos-engineering rejects non-integer header values" do
    conn = call(:get, "/chaos-engineering", [{"x-chaos-error-percentage", "abc"}])
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["detail"] == "must be an integer"
  end

  test "/chaos-engineering accepts header values at the range boundaries" do
    conn =
      call(:get, "/chaos-engineering", [
        {"x-chaos-error-percentage", "0"},
        {"x-chaos-mangled-percentage", "0"},
        {"x-chaos-latency-percentage", "0"},
        {"x-chaos-maximum-latency", "30000"}
      ])

    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["_chaos"]["maximum_latency_ms"] == 30_000
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
