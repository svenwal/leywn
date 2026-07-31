defmodule Leywn.InfoTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @opts Leywn.Router.init([])

  defp get(path), do: conn(:get, path) |> Leywn.Router.call(@opts)
  defp json(conn), do: Jason.decode!(conn.resp_body)

  # ---- /status/{code} --------------------------------------------------------

  test "any status in 100..599 is returned verbatim" do
    for code <- [200, 201, 301, 400, 418, 429, 500, 503, 599] do
      conn = get("/status/#{code}")
      assert conn.status == code
      assert json(conn)["status"] == code
    end
  end

  test "1xx, 204 and 304 respond with an empty body" do
    for code <- [100, 101, 204, 304] do
      conn = get("/status/#{code}")
      assert conn.status == code
      assert conn.resp_body == ""
    end
  end

  test "out-of-range and non-numeric status codes return 400" do
    for code <- ["99", "600", "abc", "2x0", "-1"] do
      conn = get("/status/#{code}")
      assert conn.status == 400
      assert json(conn)["error"] == "invalid_status_code"
    end
  end

  test "status works for methods other than GET" do
    conn = conn(:post, "/status/418") |> Leywn.Router.call(@opts)
    assert conn.status == 418
  end

  # ---- /uuid and /guuid ------------------------------------------------------

  @uuid_v4 ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "/uuid returns a v4 UUID" do
    assert json(get("/uuid"))["uuid"] =~ @uuid_v4
  end

  test "/guuid returns a v4 UUID wrapped in braces" do
    guuid = json(get("/guuid"))["guuid"]
    assert String.starts_with?(guuid, "{") and String.ends_with?(guuid, "}")
    assert String.slice(guuid, 1..-2//1) =~ @uuid_v4
  end

  test "successive UUIDs differ" do
    assert json(get("/uuid"))["uuid"] != json(get("/uuid"))["uuid"]
  end

  # ---- /random/int and /random/uint ------------------------------------------

  test "/random/int stays within the documented default range" do
    for _ <- 1..50 do
      assert json(get("/random/int"))["value"] in -32_000..32_000
    end
  end

  test "/random/uint is never negative" do
    for _ <- 1..50 do
      assert json(get("/random/uint"))["value"] in 0..65_535
    end
  end

  test "/random/int with an explicit range respects both bounds inclusively" do
    for _ <- 1..50 do
      assert json(get("/random/int/1/6"))["value"] in 1..6
    end

    assert json(get("/random/int/7/7"))["value"] == 7
    assert json(get("/random/int/-10/-5"))["value"] in -10..-5
  end

  test "/random/int rejects an inverted or non-numeric range" do
    for path <- ["/random/int/10/1", "/random/int/a/b", "/random/int/1/x"] do
      conn = get(path)
      assert conn.status == 400
      assert json(conn)["error"] == "invalid_range"
    end
  end

  test "/random returns one sample of every documented type" do
    body = json(get("/random"))

    for key <- ~w(int uint uuid guuid lorem_ipsum name email color) do
      assert Map.has_key?(body, key), "missing #{key}"
    end
  end

  # ---- /ip -------------------------------------------------------------------

  test "/ip reports the caller address split by family" do
    body = json(get("/ip"))
    assert Map.has_key?(body, "ipv4")
    assert Map.has_key?(body, "ipv6")
    assert body["ipv4"] == "127.0.0.1"
  end

  test "/ip/v4 and /ip/v6 return only their own family" do
    assert Map.keys(json(get("/ip/v4"))) == ["ipv4"]
    assert Map.keys(json(get("/ip/v6"))) == ["ipv6"]
  end

  # ---- /date and /time -------------------------------------------------------

  test "/date returns an ISO 8601 date in UTC" do
    body = json(get("/date"))
    assert body["timezone"] == "UTC"
    assert {:ok, _} = Date.from_iso8601(body["date"])
  end

  test "/time returns an ISO 8601 datetime in UTC" do
    body = json(get("/time"))
    assert body["timezone"] == "UTC"
    assert {:ok, _, _} = DateTime.from_iso8601(body["time"])
  end

  test "IANA timezones with a slash are resolved" do
    for tz <- ["Europe/Berlin", "America/New_York", "Asia/Tokyo"] do
      date = json(get("/date/#{tz}"))
      assert date["timezone"] == tz
      assert {:ok, _} = Date.from_iso8601(date["date"])

      time = json(get("/time/#{tz}"))
      assert time["timezone"] == tz
      assert {:ok, _, _} = DateTime.from_iso8601(time["time"])
    end
  end

  test "an unknown timezone returns 404 on both /date and /time" do
    for path <- ["/date/Invalid/Zone", "/time/Invalid/Zone", "/date/Nonsense"] do
      conn = get(path)
      assert conn.status == 404
      assert json(conn)["error"] == "unknown_timezone"
    end
  end
end
