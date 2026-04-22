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
