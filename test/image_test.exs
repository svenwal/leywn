defmodule Leywn.ImageTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @opts Leywn.Router.init([])

  defp get(path) do
    conn(:get, path)
    |> Leywn.Router.call(@opts)
  end

  # ---- Existing types --------------------------------------------------------

  test "image/png returns PNG" do
    conn = get("/image/png")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
  end

  test "image/jpeg returns JPEG" do
    conn = get("/image/jpeg")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
  end

  test "image/jpg is alias for jpeg" do
    conn = get("/image/jpg")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
  end

  test "image/gif returns GIF" do
    conn = get("/image/gif")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/gif"
  end

  test "image/webp returns the pre-generated WebP" do
    conn = get("/image/webp")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/webp"
  end

  # Binary payloads must not be labelled with a character set.
  test "binary image responses carry no charset parameter" do
    for type <- ~w(png jpeg gif webp) do
      [ct] = get("/image/#{type}") |> get_resp_header("content-type")
      refute ct =~ "charset", "#{type} content-type should not include a charset: #{ct}"
    end

    [ct] = get("/image/color/ff0000") |> get_resp_header("content-type")
    refute ct =~ "charset"
  end

  # ---- SVG -------------------------------------------------------------------

  test "image/svg returns an SVG with Leywn content" do
    conn = get("/image/svg")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "svg"
    assert conn.resp_body =~ "<svg"
    assert conn.resp_body =~ "Leywn"
    assert conn.resp_body =~ "#1a1a2e"
  end

  # ---- Unsupported type -------------------------------------------------------

  test "image/tiff returns 400" do
    conn = get("/image/tiff")
    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "unsupported_image_type"
  end

  # A known type whose file happens to be missing must report that, not crash the
  # request with a 500 out of send_file/3.
  test "a known image type with no file on disk returns 404, not a crash" do
    assert {:error, :unavailable, "image_not_available"} =
             Leywn.Logos.path_for_in("png", "/nonexistent-image-dir")
  end

  # ---- /image/color ----------------------------------------------------------

  test "image/color with 6-char hex returns PNG" do
    conn = get("/image/color/ff0000")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
    # PNG signature
    assert binary_part(conn.resp_body, 0, 4) == <<137, 80, 78, 71>>
  end

  test "image/color with 3-char hex returns PNG" do
    conn = get("/image/color/f00")
    assert conn.status == 200
    assert binary_part(conn.resp_body, 0, 4) == <<137, 80, 78, 71>>
  end

  test "image/color with 8-char hex (RGBA) returns PNG" do
    conn = get("/image/color/ff0000cc")
    assert conn.status == 200
    assert binary_part(conn.resp_body, 0, 4) == <<137, 80, 78, 71>>
  end

  test "image/color with custom dimensions returns PNG" do
    conn = get("/image/color/00ff00/128/64")
    assert conn.status == 200
    assert binary_part(conn.resp_body, 0, 4) == <<137, 80, 78, 71>>
  end

  test "image/color with invalid hex returns 400" do
    conn = get("/image/color/zzzzzz")
    assert conn.status == 400
  end

  test "image/color with invalid dimensions returns 400" do
    conn = get("/image/color/ff0000/abc/def")
    assert conn.status == 400
  end

  test "image/color with out-of-range dimensions returns 400" do
    conn = get("/image/color/ff0000/0/64")
    assert conn.status == 400
  end
end
