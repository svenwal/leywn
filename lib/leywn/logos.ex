defmodule Leywn.Logos do
  @max_dimension 4096
  @max_pixels 1_048_576
  @default_size 64

  @doc """
  Called at application startup. No-op — WebP is pre-generated at build time.
  """
  def ensure, do: :ok

  @doc """
  Returns image data for the given type string.

  Returns:
    {:ok, :file, path, content_type}   — serve from filesystem
    {:ok, :inline, data, content_type} — serve inline binary/text
    {:error, reason}
  """
  def path_for(type) when is_binary(type) do
    case String.downcase(type) do
      ext when ext in ["png", "jpeg", "jpg", "gif", "webp"] ->
        real_ext = if ext == "jpg", do: "jpeg", else: ext
        path = Application.app_dir(:leywn, "priv/images/leywn.#{real_ext}")
        {:ok, :file, path, mime(real_ext)}

      "svg" ->
        {:ok, :inline, svg_content(), "image/svg+xml"}

      _ ->
        {:error, "unsupported_image_type"}
    end
  end

  @doc """
  Generate a solid-colour PNG image.
  color_hex: 3-char, 6-char, or 8-char (RGBA) hex string.
  Returns {:ok, png_binary} or {:error, reason}.
  """
  def color_png(color_hex, width \\ @default_size, height \\ @default_size) do
    with {:ok, r, g, b, a} <- parse_hex_color(color_hex),
         :ok <- validate_dimensions(width, height) do
      {:ok, solid_png(r, g, b, a, width, height)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp svg_content do
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80" width="240" height="80">
      <rect width="240" height="80" fill="#1a1a2e"/>
      <text x="120" y="52"
            font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
            font-size="36" font-weight="600" fill="#e0e0e0" text-anchor="middle">Leywn</text>
    </svg>
    """
  end

  # ---------------------------------------------------------------------------
  # Solid-colour PNG generator (pure OTP, no external deps)
  # ---------------------------------------------------------------------------

  defp solid_png(r, g, b, 255, width, height) do
    pixel = <<r::8, g::8, b::8>>
    row = <<0::8, :binary.copy(pixel, width)::binary>>
    raw = :binary.copy(row, height)
    encode_png(<<width::32, height::32, 8, 2, 0, 0, 0>>, raw)
  end

  defp solid_png(r, g, b, a, width, height) do
    pixel = <<r::8, g::8, b::8, a::8>>
    row = <<0::8, :binary.copy(pixel, width)::binary>>
    raw = :binary.copy(row, height)
    encode_png(<<width::32, height::32, 8, 6, 0, 0, 0>>, raw)
  end

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp encode_png(ihdr_data, raw_pixels) do
    @png_signature <>
      png_chunk("IHDR", ihdr_data) <>
      png_chunk("IDAT", :zlib.compress(raw_pixels)) <>
      png_chunk("IEND", <<>>)
  end

  defp png_chunk(type, data) when is_binary(type) and is_binary(data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end

  # ---------------------------------------------------------------------------
  # Color parsing — accepts 3-char, 6-char (RGB) or 8-char (RGBA) hex
  # ---------------------------------------------------------------------------

  defp parse_hex_color(hex) do
    clean = String.trim(hex) |> String.trim_leading("#") |> String.downcase()

    case String.length(clean) do
      3 ->
        expanded = clean |> String.graphemes() |> Enum.map_join(&(&1 <> &1))
        parse_hex6(expanded)

      6 ->
        parse_hex6(clean)

      8 ->
        parse_hex8(clean)

      _ ->
        {:error, "invalid_color"}
    end
  end

  defp parse_hex6(<<r::binary-2, g::binary-2, b::binary-2>>) do
    with {rv, ""} <- Integer.parse(r, 16),
         {gv, ""} <- Integer.parse(g, 16),
         {bv, ""} <- Integer.parse(b, 16) do
      {:ok, rv, gv, bv, 255}
    else
      _ -> {:error, "invalid_color"}
    end
  end

  defp parse_hex6(_), do: {:error, "invalid_color"}

  defp parse_hex8(<<r::binary-2, g::binary-2, b::binary-2, a::binary-2>>) do
    with {rv, ""} <- Integer.parse(r, 16),
         {gv, ""} <- Integer.parse(g, 16),
         {bv, ""} <- Integer.parse(b, 16),
         {av, ""} <- Integer.parse(a, 16) do
      {:ok, rv, gv, bv, av}
    else
      _ -> {:error, "invalid_color"}
    end
  end

  defp parse_hex8(_), do: {:error, "invalid_color"}

  defp validate_dimensions(w, h)
       when w >= 1 and w <= @max_dimension and h >= 1 and h <= @max_dimension and
              w * h <= @max_pixels,
       do: :ok

  defp validate_dimensions(_, _),
    do: {:error, "dimensions_out_of_range"}

  defp mime("png"), do: "image/png"
  defp mime("jpeg"), do: "image/jpeg"
  defp mime("gif"), do: "image/gif"
  defp mime("webp"), do: "image/webp"
end
