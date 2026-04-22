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

  test "format/yaml pretty-formats valid YAML" do
    conn = post("/format/yaml", "name: Alice\nage: 30\n")
    assert conn.status == 200
    assert conn.resp_body =~ "name:"
    assert conn.resp_body =~ "Alice"
    assert conn.resp_body =~ "age:"
    assert conn.resp_body =~ "30"
    assert get_resp_header(conn, "content-type") |> hd() =~ "yaml"
  end

  test "format/yaml normalises nested YAML indentation" do
    input = "person:\n    name: Bob\n    age: 25\n"
    conn = post("/format/yaml", input)
    assert conn.status == 200
    # Re-emitted with 2-space indentation
    assert conn.resp_body =~ "person:"
    assert conn.resp_body =~ "name:"
    assert conn.resp_body =~ "Bob"
  end

  test "format/yaml returns 422 for invalid YAML" do
    conn = post("/format/yaml", "key: [\nunclosed")
    assert conn.status == 422
  end

  # ---- /format/xml -----------------------------------------------------------

  test "format/xml pretty-formats valid XML" do
    conn = post("/format/xml", "<root><child>hello</child></root>")
    assert conn.status == 200
    assert conn.resp_body =~ "<root>"
    assert conn.resp_body =~ "<child>"
    assert conn.resp_body =~ "hello"
    assert conn.resp_body =~ "</child>"
    assert String.contains?(conn.resp_body, "\n")
    assert get_resp_header(conn, "content-type") |> hd() =~ "xml"
  end

  test "format/xml adds xml declaration" do
    conn = post("/format/xml", "<a/>")
    assert conn.status == 200
    assert conn.resp_body =~ ~s(<?xml version="1.0")
  end

  test "format/xml indents nested elements" do
    conn = post("/format/xml", "<r><a><b>v</b></a></r>")
    assert conn.status == 200
    assert conn.resp_body =~ "  <a>"
    assert conn.resp_body =~ "    <b>"
    assert conn.resp_body =~ "      v"
  end

  test "format/xml returns 422 for invalid XML" do
    conn = post("/format/xml", "<unclosed>")
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
