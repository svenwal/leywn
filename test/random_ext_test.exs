defmodule Leywn.RandomExtTest do
  use ExUnit.Case
  use Plug.Test

  @opts Leywn.Router.init([])

  defp get(path) do
    conn(:get, path)
    |> Leywn.Router.call(@opts)
  end

  # ---- /random/name ----------------------------------------------------------

  test "/random/name returns a non-empty name string" do
    conn = get("/random/name")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert is_binary(body["name"])
    assert String.length(body["name"]) > 0
  end

  # ---- /random/email ---------------------------------------------------------

  test "/random/email returns a valid-looking email" do
    conn = get("/random/email")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert is_binary(body["email"])
    assert body["email"] =~ "@"
    assert body["email"] =~ "."
  end

  # ---- /random/color ---------------------------------------------------------

  test "/random/color returns hex and rgb components" do
    conn = get("/random/color")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["hex"] =~ ~r/^#[0-9a-f]{6}$/
    assert body["r"] in 0..255
    assert body["g"] in 0..255
    assert body["b"] in 0..255
  end

  # ---- /random/lorem-ipsum ---------------------------------------------------

  test "/random/lorem-ipsum returns one paragraph" do
    conn = get("/random/lorem-ipsum")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert length(body["paragraphs"]) == 1
  end

  test "/random/lorem-ipsum/3 returns 3 paragraphs" do
    conn = get("/random/lorem-ipsum/3")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert length(body["paragraphs"]) == 3
  end

  test "/random/lorem-ipsum/32 returns 32 paragraphs (maximum)" do
    conn = get("/random/lorem-ipsum/32")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert length(body["paragraphs"]) == 32
  end

  test "/random/lorem-ipsum/33 returns 400" do
    conn = get("/random/lorem-ipsum/33")
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "count_too_large"
    assert body["maximum"] == 32
    assert body["provided"] == 33
  end

  test "/random/lorem-ipsum/1000 returns 400" do
    conn = get("/random/lorem-ipsum/1000")
    assert conn.status == 400
  end

  test "/random/lorem-ipsum/0 returns 400" do
    conn = get("/random/lorem-ipsum/0")
    assert conn.status == 400
  end

  test "/random/lorem-ipsum/abc returns 400" do
    conn = get("/random/lorem-ipsum/abc")
    assert conn.status == 400
  end

  # ---- /random bundle includes new fields ------------------------------------

  test "/random bundle includes name, email, color" do
    conn = get("/random")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert Map.has_key?(body, "name")
    assert Map.has_key?(body, "email")
    assert Map.has_key?(body, "color")
  end
end
