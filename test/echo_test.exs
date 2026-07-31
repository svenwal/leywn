defmodule Leywn.EchoTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @opts Leywn.Router.init([])

  defp call(method, path, body \\ nil, headers \\ []) do
    conn(method, path, body)
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> Leywn.Router.call(@opts)
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  # ---- Basic shape -----------------------------------------------------------

  test "GET /echo reflects method, scheme, path and timestamp" do
    conn = call(:get, "/echo")
    assert conn.status == 200
    body = json(conn)

    assert body["method"] == "GET"
    assert body["scheme"] == "http"
    assert body["path"] == "/echo"
    assert is_integer(body["timestamp_unix_ms"])
  end

  test "echo path always starts with a leading slash" do
    for path <- ["/echo", "/echo/foo/bar", "/anything", "/anything/x"] do
      assert json(call(:get, path))["path"] == path
    end
  end

  test "sub-paths are matched and reported in path_info" do
    body = json(call(:get, "/echo/foo/bar"))
    assert body["path"] == "/echo/foo/bar"
    assert body["path_info"] == ["echo", "foo", "bar"]
  end

  test "query parameters are parsed and echoed" do
    body = json(call(:get, "/echo?hello=world&n=2"))
    assert body["query_string"] == "hello=world&n=2"
    assert body["query_params"] == %{"hello" => "world", "n" => "2"}
  end

  # ---- Headers ---------------------------------------------------------------
  # sub-docs/endpoints/echo.md: a header with a single value must be returned as
  # that value, not as a one-element array.

  test "a header sent once is echoed as a scalar, not an array" do
    body = json(call(:get, "/echo", nil, [{"x-single", "one"}]))
    assert body["headers"]["x-single"] == "one"
  end

  test "a header sent more than once is echoed as a list" do
    body = json(call(:get, "/echo", nil, [{"x-multi", "a"}, {"x-multi", "b"}]))
    assert body["headers"]["x-multi"] == ["a", "b"]
  end

  # ---- Methods ---------------------------------------------------------------

  test "all common methods are accepted on /echo and /anything" do
    for method <- [:get, :post, :put, :patch, :delete],
        path <- ["/echo", "/anything"] do
      conn = call(method, path)
      assert conn.status == 200
      assert json(conn)["method"] == String.upcase(to_string(method))
    end
  end

  # ---- Body ------------------------------------------------------------------

  test "a UTF-8 body is included verbatim with its byte count" do
    body = json(call(:post, "/echo", ~s({"message":"test"})))["body"]

    assert body["present"] == true
    assert body["utf8"] == true
    assert body["included"] == true
    assert body["truncated"] == false
    assert body["body"] == ~s({"message":"test"})
    assert body["bytes"] == 18
  end

  test "an absent body is reported as not present" do
    body = json(call(:get, "/echo"))["body"]
    assert body["present"] == false
    assert body["bytes"] == 0
    assert body["body"] == nil
  end

  test "a binary body is acknowledged but excluded" do
    body = json(call(:post, "/echo", <<0xFF, 0xFE, 0x00, 0x01>>))["body"]

    assert body["present"] == true
    assert body["utf8"] == false
    assert body["included"] == false
    assert body["reason"] == "binary_or_invalid_utf8"
    assert body["body"] == nil
  end

  test "a body over the limit is truncated rather than rejected" do
    limit = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    body = json(call(:post, "/echo", String.duplicate("a", limit + 1_000)))["body"]

    assert body["present"] == true
    assert body["truncated"] == true
    assert body["reason"] == "truncated"
  end

  # ---- /anything is a true alias ---------------------------------------------

  test "/anything returns the same shape as /echo" do
    echo_keys = call(:get, "/echo") |> json() |> Map.keys() |> Enum.sort()
    anything_keys = call(:get, "/anything") |> json() |> Map.keys() |> Enum.sort()
    assert echo_keys == anything_keys
  end

  # ---- Unknown routes --------------------------------------------------------

  test "an unknown path returns 404 not_found" do
    conn = call(:get, "/no/such/route")
    assert conn.status == 404
    assert json(conn)["error"] == "not_found"
  end
end
