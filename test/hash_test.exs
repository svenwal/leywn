defmodule Leywn.HashTest do
  use ExUnit.Case
  use Plug.Test

  @opts Leywn.Router.init([])

  defp post(path, body) do
    conn(:post, path, body)
    |> put_req_header("content-type", "text/plain")
    |> Leywn.Router.call(@opts)
  end

  # ---- /hash/sha256 ----------------------------------------------------------

  test "sha256 of known input matches expected digest" do
    conn = post("/hash/sha256", "hello")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["hash"] == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    assert body["algorithm"] == "sha256"
    assert body["input_bytes"] == 5
  end

  test "sha256 of empty body returns valid digest" do
    conn = post("/hash/sha256", "")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["hash"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert body["input_bytes"] == 0
  end

  # ---- /hash/md5 -------------------------------------------------------------

  test "md5 of known input matches expected digest" do
    conn = post("/hash/md5", "hello")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["hash"] == "5d41402abc4b2a76b9719d911017c592"
    assert body["algorithm"] == "md5"
    assert body["input_bytes"] == 5
  end

  test "md5 of empty body returns valid digest" do
    conn = post("/hash/md5", "")
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["hash"] == "d41d8cd98f00b204e9800998ecf8427e"
    assert body["input_bytes"] == 0
  end
end
