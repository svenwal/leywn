defmodule Leywn.YAML do
  @moduledoc """
  Minimal YAML emitter for JSON-compatible data structures.
  No external dependency — covers maps, lists, strings, numbers, booleans, nil.
  """

  @doc "Encode a value (as produced by Jason.decode/1) as a YAML string."
  def encode(value), do: serialize(value, 0) <> "\n"

  # Scalars
  defp serialize(nil, _), do: "null"
  defp serialize(true, _), do: "true"
  defp serialize(false, _), do: "false"
  defp serialize(n, _) when is_integer(n), do: Integer.to_string(n)
  defp serialize(f, _) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 10])
  defp serialize(s, _) when is_binary(s), do: quote_str(s)

  # Empty collections
  defp serialize(map, _) when is_map(map) and map_size(map) == 0, do: "{}"
  defp serialize([], _), do: "[]"

  # Map
  defp serialize(map, indent) when is_map(map) do
    pad = String.duplicate("  ", indent)

    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map_join("\n", fn {k, v} ->
      key = to_string(k)

      case v do
        v when (is_map(v) and map_size(v) > 0) or (is_list(v) and v != []) ->
          "#{pad}#{key}:\n#{serialize(v, indent + 1)}"

        _ ->
          "#{pad}#{key}: #{serialize(v, 0)}"
      end
    end)
  end

  # List
  defp serialize(list, indent) when is_list(list) do
    pad = String.duplicate("  ", indent)
    child_indent = indent + 1

    Enum.map_join(list, "\n", fn item ->
      case item do
        m when is_map(m) and map_size(m) > 0 ->
          # Render map at child_indent, then re-prefix lines:
          # first line: "- key: val" (strip child indent, add "- ")
          # other lines: "  key: val" (strip child indent, add "  ")
          inner = serialize(m, child_indent)
          strip = child_indent * 2

          inner
          |> String.split("\n")
          |> Enum.with_index()
          |> Enum.map_join("\n", fn
            {line, 0} -> "#{pad}- #{strip_prefix(line, strip)}"
            {line, _} -> "#{pad}  #{strip_prefix(line, strip)}"
          end)

        _ ->
          "#{pad}- #{serialize(item, 0)}"
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # String quoting helpers
  # ---------------------------------------------------------------------------

  @yaml_special_chars ["\n", "\t", ":", "#", "[", "]", "{", "}", ",",
                        "&", "*", "?", "|", "-", "<", ">", "=", "!",
                        "%", "@", "`", "\\", "\"", "'"]
  @yaml_reserved_words ~w(true false null yes no on off)

  defp quote_str(""), do: "\"\""

  defp quote_str(s) do
    if needs_quoting?(s) do
      ~s("#{escape(s)}")
    else
      s
    end
  end

  defp needs_quoting?(s) do
    Enum.any?(@yaml_special_chars, &String.contains?(s, &1)) or
      s in @yaml_reserved_words or
      s =~ ~r/^\s|\s$/ or
      match?({_, ""}, Integer.parse(s)) or
      match?({_, ""}, Float.parse(s))
  end

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp strip_prefix(line, n) when byte_size(line) >= n,
    do: binary_part(line, n, byte_size(line) - n)

  defp strip_prefix(line, _), do: line
end
