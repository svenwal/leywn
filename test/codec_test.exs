defmodule Leywn.CodecTest do
  use ExUnit.Case
  use Plug.Test

  @opts Leywn.Router.init([])

  defp post(path, body) do
    conn(:post, path, body)
    |> put_req_header("content-type", "text/plain")
    |> Leywn.Router.call(@opts)
  end

  # ---- /encode/base64 --------------------------------------------------------

  test "encode/base64 encodes text" do
    conn = post("/encode/base64", "hello world")
    assert conn.status == 200
    assert conn.resp_body == Base.encode64("hello world")
  end

  test "encode/base64 handles empty body" do
    conn = post("/encode/base64", "")
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  # ---- /decode/base64 --------------------------------------------------------

  test "decode/base64 decodes valid base64" do
    conn = post("/decode/base64", Base.encode64("hello world"))
    assert conn.status == 200
    assert conn.resp_body == "hello world"
  end

  test "decode/base64 returns 422 for invalid base64" do
    conn = post("/decode/base64", "not!!valid!!base64!!")
    assert conn.status == 422
  end

  # ---- /encode/url -----------------------------------------------------------

  test "encode/url percent-encodes special characters" do
    conn = post("/encode/url", "hello world & foo=bar")
    assert conn.status == 200
    assert conn.resp_body =~ "%20"
  end

  # ---- /decode/url -----------------------------------------------------------

  test "decode/url decodes percent-encoded text" do
    conn = post("/decode/url", "hello%20world")
    assert conn.status == 200
    assert conn.resp_body == "hello world"
  end

  # ---- /encode/rot13 ---------------------------------------------------------

  test "encode/rot13 applies ROT13" do
    conn = post("/encode/rot13", "Hello World")
    assert conn.status == 200
    assert conn.resp_body == "Uryyb Jbeyq"
  end

  # ---- /decode/rot13 ---------------------------------------------------------

  test "decode/rot13 is the same operation as encode (ROT13 is symmetric)" do
    conn = post("/decode/rot13", "Uryyb Jbeyq")
    assert conn.status == 200
    assert conn.resp_body == "Hello World"
  end

  test "rot13 leaves non-alpha characters unchanged" do
    conn = post("/encode/rot13", "foo-bar_123")
    assert conn.status == 200
    assert conn.resp_body == "sbb-one_123"
  end

  # ---- /decode/jwt -----------------------------------------------------------

  test "decode/jwt decodes a valid JWT" do
    # header: {"alg":"HS256","typ":"JWT"}, payload: {"sub":"user123"}
    header = Base.url_encode64(~s({"alg":"HS256","typ":"JWT"}), padding: false)
    payload = Base.url_encode64(~s({"sub":"user123"}), padding: false)
    token = "#{header}.#{payload}.fakesig"

    conn = post("/decode/jwt", token)
    assert conn.status == 200

    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["header"]["alg"] == "HS256"
    assert body["payload"]["sub"] == "user123"
  end

  test "decode/jwt returns 422 for invalid token" do
    conn = post("/decode/jwt", "notavalidjwt")
    assert conn.status == 422
  end

  test "decode/jwt returns 422 for malformed JWT parts" do
    conn = post("/decode/jwt", "bad.!!!.sig")
    assert conn.status == 422
  end

  # ---- /encode/hex -----------------------------------------------------------

  test "encode/hex encodes text as lowercase hex" do
    conn = post("/encode/hex", "hello")
    assert conn.status == 200
    assert conn.resp_body == "68656c6c6f"
  end

  test "encode/hex handles empty body" do
    conn = post("/encode/hex", "")
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  # ---- /decode/hex -----------------------------------------------------------

  test "decode/hex decodes valid hex string" do
    conn = post("/decode/hex", "68656c6c6f")
    assert conn.status == 200
    assert conn.resp_body == "hello"
  end

  test "decode/hex is case-insensitive" do
    conn = post("/decode/hex", "48656C6C6F")
    assert conn.status == 200
    assert conn.resp_body == "Hello"
  end

  test "decode/hex returns 422 for invalid hex" do
    conn = post("/decode/hex", "zzzz")
    assert conn.status == 422
  end
end
