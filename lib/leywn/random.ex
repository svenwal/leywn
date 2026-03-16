defmodule Leywn.Random do
  @moduledoc "Helpers for all /random and /uuid endpoints."
  import Bitwise

  # Classic opening sentence kept intact; rest is generated from word pool
  @first_sentence "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

  @words ~w(
    lorem ipsum dolor sit amet consectetur adipiscing elit sed eiusmod tempor
    incididunt labore dolore magna aliqua enim minim veniam quis nostrud
    exercitation ullamco laboris nisi aliquip commodo consequat duis aute
    irure reprehenderit voluptate velit esse cillum fugiat nulla pariatur
    excepteur sint occaecat cupidatat proident culpa officia deserunt mollit
    anim laborum viverra accumsan lacus vel facilisis volutpat est velit
    egestas dui sapien eget mi proin sed libero enim sed faucibus turpis
    tincidunt id aliquet risus feugiat pretium nibh ipsum consequat nisl vel
    pretium lectus quam id leo duis tristique sollicitudin nibh sit amet
    commodo nulla facilisi nullam vehicula ipsum
  )

  # ── UUID / GUID ──────────────────────────────────────────────────────────────

  @doc "Generate a random UUID v4 string."
  def uuid do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, 0x4000 ||| c, 0x8000 ||| d, e]
    )
    |> IO.iodata_to_binary()
  end

  @doc "Generate a GUID (UUID v4 wrapped in curly braces)."
  def guuid, do: "{#{uuid()}}"

  # ── Integers ─────────────────────────────────────────────────────────────────

  @doc "Random signed integer in [-32_000, 32_000]."
  def random_int, do: random_int(-32_000, 32_000)

  @doc "Random signed integer in [min, max]."
  def random_int(min, max) when is_integer(min) and is_integer(max) and min <= max do
    min + :rand.uniform(max - min + 1) - 1
  end

  @doc "Random unsigned integer in [0, 65_535]."
  def random_uint, do: random_int(0, 65_535)

  # ── Lorem ipsum ──────────────────────────────────────────────────────────────

  @doc "Return `n` paragraphs of Lorem Ipsum (max 32)."
  def lorem_ipsum(n) when is_integer(n) and n >= 1 do
    count = min(n, 32)
    Enum.map(1..count, &build_paragraph/1)
  end

  defp build_paragraph(1) do
    # First paragraph always opens with the classic sentence
    rest = Enum.map(1..4, fn _ -> random_sentence() end) |> Enum.join(" ")
    @first_sentence <> " " <> rest
  end

  defp build_paragraph(_), do: Enum.map(1..5, fn _ -> random_sentence() end) |> Enum.join(" ")

  defp random_sentence do
    count = 8 + :rand.uniform(8)
    words = Enum.map(1..count, fn _ -> Enum.random(@words) end)
    [h | t] = words
    String.capitalize(h) <> " " <> Enum.join(t, " ") <> "."
  end
end
