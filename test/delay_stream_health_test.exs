defmodule Leywn.DelayStreamHealthTest do
  use ExUnit.Case
  use Plug.Test

  @opts Leywn.Router.init([])

  defp get(path) do
    conn(:get, path)
    |> Leywn.Router.call(@opts)
  end

  # ---- /health ---------------------------------------------------------------

  test "/health returns ok status and version" do
    conn = get("/health")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["status"] == "ok"
    assert is_binary(body["version"])
    assert is_integer(body["uptime_seconds"])
    assert body["uptime_seconds"] >= 0
  end

  # ---- /delay ----------------------------------------------------------------

  test "/delay/0 responds immediately with delay info" do
    conn = get("/delay/0")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["delayed_ms"] == 0
    assert body["requested_ms"] == 0
  end

  test "/delay/10 delays briefly" do
    t0 = System.monotonic_time(:millisecond)
    conn = get("/delay/10")
    elapsed = System.monotonic_time(:millisecond) - t0
    assert conn.status == 200
    assert elapsed >= 10
  end

  test "/delay returns 400 for value exceeding 30 000 ms maximum" do
    conn = get("/delay/999999")
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "delay_too_large"
    assert body["maximum_ms"] == 30_000
    assert body["provided_ms"] == 999_999
  end

  test "/delay/30000 is accepted (at the limit)" do
    conn = get("/delay/30000")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["delayed_ms"] == 30_000
  end

  test "/delay returns 400 for non-integer" do
    conn = get("/delay/abc")
    assert conn.status == 400
  end

  test "/delay returns 400 for negative value" do
    conn = get("/delay/-5")
    assert conn.status == 400
  end

  # ---- /stream ---------------------------------------------------------------

  test "/stream/5 returns 5 ndjson lines" do
    conn = get("/stream/5")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-ndjson"
    lines = conn.resp_body |> String.split("\n", trim: true)
    assert length(lines) == 5
    Enum.each(lines, fn line ->
      {:ok, obj} = Jason.decode(line)
      assert Map.has_key?(obj, "line")
      assert Map.has_key?(obj, "total")
      assert obj["total"] == 5
    end)
  end

  test "/stream returns 400 for value exceeding 100 lines maximum" do
    conn = get("/stream/200")
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "count_too_large"
    assert body["maximum"] == 100
    assert body["provided"] == 200
  end

  test "/stream/100 is accepted (at the limit)" do
    conn = get("/stream/100")
    assert conn.status == 200
    lines = conn.resp_body |> String.split("\n", trim: true)
    assert length(lines) == 100
  end

  test "/stream/1 returns exactly one line" do
    conn = get("/stream/1")
    assert conn.status == 200
    lines = conn.resp_body |> String.split("\n", trim: true)
    assert length(lines) == 1
    {:ok, obj} = Jason.decode(hd(lines))
    assert obj["line"] == 1
  end

  test "/stream returns 400 for invalid count" do
    conn = get("/stream/abc")
    assert conn.status == 400
  end

  test "/stream returns 400 for zero" do
    conn = get("/stream/0")
    assert conn.status == 400
  end

  # ---- /request-collection ---------------------------------------------------

  test "/request-collection returns valid Insomnia v4 JSON" do
    conn = get("/request-collection")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["__export_format"] == 4
    assert body["_type"] == "export"
    resources = body["resources"]
    assert is_list(resources)
    types = Enum.map(resources, & &1["_type"])
    assert "workspace" in types
    assert "environment" in types
    assert "request_group" in types
    assert "request" in types
  end

  test "/request-collection content-disposition is attachment" do
    conn = get("/request-collection")
    assert conn.status == 200
    [cd] = get_resp_header(conn, "content-disposition")
    assert cd =~ "attachment"
    assert cd =~ "leywn.insomnia.json"
  end

  test "/request-collection environment has base_url" do
    conn = get("/request-collection")
    {:ok, body} = Jason.decode(conn.resp_body)
    env = Enum.find(body["resources"], &(&1["_type"] == "environment"))
    assert get_in(env, ["data", "base_url"]) =~ "localhost"
  end

  test "/request-collection covers all endpoint groups" do
    conn = get("/request-collection")
    {:ok, body} = Jason.decode(conn.resp_body)
    folder_names = body["resources"]
    |> Enum.filter(&(&1["_type"] == "request_group"))
    |> Enum.map(& &1["name"])
    for group <- ~w(Utility Echo Auth Random Info Format Codec Hash) do
      assert group in folder_names, "Missing folder: #{group}"
    end
  end

  # ---- CORS ------------------------------------------------------------------

  test "CORS headers are present on normal responses" do
    conn = get("/health")
    assert get_resp_header(conn, "access-control-allow-origin") != []
  end

  test "OPTIONS request returns 204 with CORS headers" do
    conn =
      conn(:options, "/health")
      |> Leywn.Router.call(@opts)

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-methods") != []
  end
end
