defmodule Leywn.SecurityTest do
  # Environment variables are process-global, so these cannot run concurrently.
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureIO

  @opts Leywn.Router.init([])

  defp call(method, path, body \\ nil, headers \\ []) do
    headers
    |> Enum.reduce(conn(method, path, body), fn {k, v}, c -> put_req_header(c, k, v) end)
    |> Leywn.Router.call(@opts)
  end

  defp with_env(var, value, fun) do
    previous = System.get_env(var)
    System.put_env(var, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(var, previous), else: System.delete_env(var)
    end
  end

  defp jwt(header, payload) do
    enc = &Base.url_encode64(Jason.encode!(&1), padding: false)
    enc.(header) <> "." <> enc.(payload) <> ".sig"
  end

  # ---- Response headers -------------------------------------------------------

  test "every response carries X-Content-Type-Options: nosniff" do
    for path <- ["/health", "/nope", "/uuid"] do
      assert get_resp_header(call(:get, path), "x-content-type-options") == ["nosniff"]
    end

    assert get_resp_header(call(:post, "/decode/base64", "PGI+"), "x-content-type-options") ==
             ["nosniff"]
  end

  # ---- Amplification through nesting -------------------------------------------

  test "format/json rejects deeply nested input instead of expanding it" do
    body = String.duplicate("[", 20_000) <> String.duplicate("]", 20_000)
    conn = call(:post, "/format/json", body)
    assert conn.status == 422
    assert byte_size(conn.resp_body) < 1_000
  end

  test "format/json still accepts ordinary nesting" do
    body = String.duplicate("[", 30) <> String.duplicate("]", 30)
    assert call(:post, "/format/json", body).status == 200
  end

  test "decode/jwt rejects a deeply nested payload" do
    deep = String.duplicate("[", 20_000) <> String.duplicate("]", 20_000)

    token =
      Base.url_encode64(~s({"alg":"none"}), padding: false) <>
        "." <>
        Base.url_encode64(~s({"a":#{deep}}), padding: false) <> ".x"

    assert call(:post, "/decode/jwt", token).status == 422
  end

  test "format/xml rejects deeply nested elements" do
    body = String.duplicate("<a>", 5_000) <> String.duplicate("</a>", 5_000)
    conn = call(:post, "/format/xml", body)
    assert conn.status == 422
  end

  test "format/xml still accepts ordinary nesting" do
    body = String.duplicate("<a>", 20) <> "x" <> String.duplicate("</a>", 20)
    assert call(:post, "/format/xml", body).status == 200
  end

  test "format/yaml rejects an alias expansion bomb" do
    level = fn name -> Enum.map_join(1..10, "\n", fn _ -> "  - *#{name}" end) end

    bomb =
      "a: &a\n  - x\n  - y\n" <>
        Enum.map_join(~w(b:a c:b d:c e:d), "\n", fn pair ->
          [name, from] = String.split(pair, ":")
          "#{name}: &#{name}\n" <> level.(from)
        end)

    conn = call(:post, "/format/yaml", bomb)
    assert conn.status == 422
    assert conn.resp_body =~ "too complex"
  end

  test "format/yaml still accepts ordinary documents" do
    assert call(:post, "/format/yaml", "a: 1\nb: [x, y]\n").status == 200
  end

  # ---- Quadratic parsing ------------------------------------------------------

  test "format/xml does not take quadratic time on unterminated markup" do
    for body <- [
          String.duplicate("<!--", 15_000),
          String.duplicate("<![CDATA[", 7_000),
          String.duplicate("<?", 15_000),
          String.duplicate("<", 30_000) <> ">",
          "<a>" <> String.duplicate("<", 30_000)
        ] do
      {micros, conn} = :timer.tc(fn -> call(:post, "/format/xml", body) end)
      assert conn.status == 422
      assert micros < 1_000_000
    end
  end

  # ---- Malformed input must be a 4xx, never a 500 ------------------------------

  test "token exchange with malformed percent-encoding is a 400" do
    conn =
      call(:post, "/auth/jwt/exchange", "subject_token=%zz&grant_type=x", [
        {"content-type", "application/x-www-form-urlencoded"}
      ])

    assert conn.status == 400
  end

  test "Bearer exchange with non-object claims is a 401" do
    for payload <- [[1, 2, 3], "text", 7] do
      token = jwt(%{"alg" => "HS256"}, payload)
      conn = call(:post, "/auth/jwt/exchange", nil, [{"authorization", "Bearer " <> token}])
      assert conn.status == 401
    end

    token = jwt(%{"alg" => "HS256"}, [1])
    assert call(:get, "/auth/jwt", nil, [{"authorization", "Bearer " <> token}]).status == 401
  end

  test "mTLS header mode answers 401 for malformed percent-encoding or PEM" do
    with_env("LEYWN_MTLS_IN_HEADER", "x-client-cert", fn ->
      for value <- ["%zz", "-----BEGIN CERTIFICATE-----%0A!!!%0A-----END CERTIFICATE-----"] do
        conn = call(:get, "/auth/mtls", nil, [{"x-client-cert", value}])
        assert conn.status == 401
      end
    end)
  end

  # ---- Forwarded address ------------------------------------------------------

  test "X-Forwarded-For is only reflected when it is an IP address" do
    with_env("LEYWN_TRUST_FORWARD", "true", fn ->
      ok = call(:get, "/ip/v4", nil, [{"x-forwarded-for", "203.0.113.9, 10.0.0.1"}])
      assert Jason.decode!(ok.resp_body)["ipv4"] == "203.0.113.9"

      bad = call(:get, "/ip/v4", nil, [{"x-forwarded-for", "<script>alert(1)</script>"}])
      assert Jason.decode!(bad.resp_body)["ipv4"] == nil
    end)
  end

  # ---- Log forging ------------------------------------------------------------

  test "control characters in the request path cannot forge log lines" do
    output =
      capture_io(fn ->
        %{
          conn(:get, "/x")
          | request_path: "/a\n2026-01-01T00:00:00Z GET /forged status=200\r\x1b[2J"
        }
        |> Leywn.RequestLogger.call([])
        |> send_resp(200, "")
      end)

    assert length(String.split(String.trim_trailing(output), "\n")) == 1
    refute output =~ "\x1b"
  end

  # ---- Sleeping requests ------------------------------------------------------

  test "/delay answers 503 once the concurrent-delay ceiling is reached" do
    with_env("LEYWN_MAX_CONCURRENT_DELAYS", "0", fn ->
      conn = call(:get, "/delay/10")
      assert conn.status == 503
      assert get_resp_header(conn, "retry-after") == ["1"]
    end)
  end

  test "chaos latency answers 503 once the concurrent-delay ceiling is reached" do
    with_env("LEYWN_MAX_CONCURRENT_DELAYS", "0", fn ->
      assert call(:get, "/chaos-engineering/0/0/100/50").status == 503
    end)
  end

  test "/delay releases its slot when it finishes" do
    with_env("LEYWN_MAX_CONCURRENT_DELAYS", "1", fn ->
      for _ <- 1..3, do: assert(call(:get, "/delay/5").status == 200)
      assert :ets.info(:leywn_sleepers, :size) == 0
    end)
  end

  test "a slot held by a dead process is reclaimed" do
    with_env("LEYWN_MAX_CONCURRENT_DELAYS", "1", fn ->
      {pid, ref} = spawn_monitor(fn -> :ets.insert(:leywn_sleepers, {self()}) end)
      assert_receive {:DOWN, ^ref, _, _, _}
      assert :ets.member(:leywn_sleepers, pid)
      assert call(:get, "/delay/5").status == 200
      refute :ets.member(:leywn_sleepers, pid)
    end)
  end

  # ---- Image memory -----------------------------------------------------------

  test "a large solid-colour PNG is valid and compact" do
    conn = call(:get, "/image/color/ff0000/4096/256")
    assert conn.status == 200
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = conn.resp_body
    assert byte_size(conn.resp_body) < 100_000

    # The IDAT stream must inflate back to height * (1 + width * 3) bytes.
    <<_sig::binary-8, _len::32, "IHDR", _ihdr::binary-13, _crc::32, len::32, "IDAT",
      idat::binary-size(len), _rest::binary>> = conn.resp_body

    assert byte_size(:zlib.uncompress(idat)) == 256 * (1 + 4096 * 3)
  end
end
