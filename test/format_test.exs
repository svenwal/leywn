defmodule Leywn.FormatTest do
  use ExUnit.Case
  use Plug.Test

  @opts Leywn.Router.init([])

  defp post(path, body, content_type \\ "text/plain") do
    conn(:post, path, body)
    |> put_req_header("content-type", content_type)
    |> Leywn.Router.call(@opts)
  end

  # ---- /format/json ----------------------------------------------------------

  test "format/json pretty-prints valid JSON" do
    conn = post("/format/json", ~s({"b":2,"a":1}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "\"a\""
    assert conn.resp_body =~ "\"b\""
    # Pretty-printed: must have newlines
    assert String.contains?(conn.resp_body, "\n")
  end

  test "format/json returns 422 for invalid JSON" do
    conn = post("/format/json", "not json")
    assert conn.status == 422
  end

  # ---- /format/yaml ----------------------------------------------------------

  test "format/yaml converts valid JSON to YAML" do
    conn = post("/format/yaml", ~s({"name":"Alice","age":30}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "name: Alice"
    assert conn.resp_body =~ "age: 30"
    assert get_resp_header(conn, "content-type") |> hd() =~ "yaml"
  end

  test "format/yaml returns 422 for invalid JSON" do
    conn = post("/format/yaml", "not json")
    assert conn.status == 422
  end

  # ---- /format/xml -----------------------------------------------------------

  test "format/xml converts valid JSON to XML" do
    conn = post("/format/xml", ~s({"key":"value"}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "<key>"
    assert conn.resp_body =~ "value"
    assert get_resp_header(conn, "content-type") |> hd() =~ "xml"
  end

  test "format/xml returns 422 for invalid JSON" do
    conn = post("/format/xml", "<invalid>not json")
    assert conn.status == 422
  end

  # ---- /format/camelCase -----------------------------------------------------

  test "format/camelCase converts snake_case keys" do
    conn = post("/format/camelCase", ~s({"first_name":"Alice","last_name":"Smith"}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "firstName"
    assert conn.resp_body =~ "lastName"
    refute conn.resp_body =~ "first_name"
  end

  test "format/camelCase returns 422 for invalid JSON" do
    conn = post("/format/camelCase", "not json")
    assert conn.status == 422
  end

  # ---- /format/kebab-case ----------------------------------------------------

  test "format/kebab-case converts camelCase keys" do
    conn = post("/format/kebab-case", ~s({"firstName":"Alice","lastName":"Smith"}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "first-name"
    assert conn.resp_body =~ "last-name"
    refute conn.resp_body =~ "firstName"
  end

  test "format/kebab-case returns 422 for invalid JSON" do
    conn = post("/format/kebab-case", "not json")
    assert conn.status == 422
  end

  # ---- /format/snake-case ----------------------------------------------------

  test "format/snake-case converts camelCase keys" do
    conn = post("/format/snake-case", ~s({"firstName":"Alice","lastName":"Smith"}), "application/json")
    assert conn.status == 200
    assert conn.resp_body =~ "first_name"
    assert conn.resp_body =~ "last_name"
    refute conn.resp_body =~ "firstName"
  end

  test "format/snake-case returns 422 for invalid JSON" do
    conn = post("/format/snake-case", "not json")
    assert conn.status == 422
  end

  # ---- /format/toUpper -------------------------------------------------------

  test "format/toUpper uppercases text" do
    conn = post("/format/toUpper", "hello world")
    assert conn.status == 200
    assert conn.resp_body == "HELLO WORLD"
  end

  test "format/toUpper works on empty body" do
    conn = post("/format/toUpper", "")
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  # ---- /format/toLower -------------------------------------------------------

  test "format/toLower lowercases text" do
    conn = post("/format/toLower", "HELLO WORLD")
    assert conn.status == 200
    assert conn.resp_body == "hello world"
  end

  # ---- /format/collapse-lines ------------------------------------------------

  test "format/collapse-lines collapses multiple blank lines" do
    conn = post("/format/collapse-lines", "line1\n\n\n\nline2\n\nline3")
    assert conn.status == 200
    assert conn.resp_body == "line1\n\nline2\n\nline3"
    refute conn.resp_body =~ "\n\n\n"
  end

  test "format/collapse-lines leaves single blank lines intact" do
    conn = post("/format/collapse-lines", "a\n\nb")
    assert conn.status == 200
    assert conn.resp_body == "a\n\nb"
  end
end
