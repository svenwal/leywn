defmodule Leywn.Format do
  @moduledoc """
  POST body format / prettify transformations.
  Each function returns {:ok, content_type, body} or {:error, message}.
  """

  # Pretty-printing indents every level, so output grows with the square of the
  # nesting depth: a 64 KiB body of [[[[...]]]] would otherwise expand to
  # hundreds of megabytes. Real JSON is nowhere near this deep.
  @max_depth 64

  @doc "Pretty-print a JSON body (nesting up to #{@max_depth} levels)."
  def json(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        if Leywn.Shape.deeper_than?(data, @max_depth) do
          {:error, "JSON nested too deeply (max #{@max_depth} levels)"}
        else
          {:ok, "application/json", Jason.encode!(data, pretty: true)}
        end

      {:error, _} ->
        {:error, "invalid JSON input"}
    end
  end

  @yaml_max_bytes 16_384

  @doc "Pretty-format a YAML body (max #{@yaml_max_bytes} bytes)."
  def yaml(body) do
    if byte_size(body) > @yaml_max_bytes do
      {:error, "YAML input too large (max #{@yaml_max_bytes} bytes)"}
    else
      try do
        case YamlElixir.read_from_string(body) do
          {:ok, data} -> yaml_result(data)
          {:error, _} -> {:error, "invalid YAML input"}
        end
      rescue
        _ -> {:error, "invalid YAML input"}
      catch
        _, _ -> {:error, "invalid YAML input"}
      end
    end
  end

  # YAML aliases let a few kilobytes describe an enormous document (each level
  # of `*a` references the previous one several times over). The parser shares
  # the structure, but re-emitting it expands every reference, so the parsed
  # result is measured under a node budget before anything is written out.
  @yaml_max_nodes 10_000
  @yaml_max_depth 64

  defp yaml_result(data) do
    if match?({:ok, _}, spend(data, 0, @yaml_max_nodes)) do
      {:ok, "application/yaml", Leywn.YAML.encode(data)}
    else
      {:error, "YAML input too complex (max #{@yaml_max_nodes} nodes, #{@yaml_max_depth} levels)"}
    end
  end

  defp spend(_value, depth, budget) when budget <= 0 or depth > @yaml_max_depth, do: :over

  defp spend(value, depth, budget) when is_map(value) do
    spend(Enum.flat_map(value, fn {k, v} -> [k, v] end), depth, budget)
  end

  defp spend(value, depth, budget) when is_list(value) do
    Enum.reduce_while(value, {:ok, budget - 1}, fn child, {:ok, left} ->
      case spend(child, depth + 1, left) do
        {:ok, _} = ok -> {:cont, ok}
        :over -> {:halt, :over}
      end
    end)
  end

  defp spend(_scalar, _depth, budget), do: {:ok, budget - 1}

  @doc "Pretty-format an XML body with consistent 2-space indentation."
  def xml(body) do
    case pretty_xml(String.trim(body)) do
      {:ok, formatted} -> {:ok, "application/xml", formatted}
      :error -> {:error, "invalid XML input"}
    end
  end

  @doc "Convert body text to camelCase."
  def camel_case(body), do: {:ok, "text/plain", to_camel(body)}

  @doc "Convert body text to kebab-case."
  def kebab_case(body), do: {:ok, "text/plain", to_kebab(body)}

  @doc "Convert body text to snake_case."
  def snake_case(body), do: {:ok, "text/plain", to_snake(body)}

  @doc "Convert the body text to uppercase."
  def to_upper(body), do: {:ok, "text/plain", String.upcase(body)}

  @doc "Convert the body text to lowercase."
  def to_lower(body), do: {:ok, "text/plain", String.downcase(body)}

  @doc "Collapse multiple consecutive blank lines into a single blank line."
  def collapse_lines(body) do
    result = Regex.replace(~r/\n{3,}/, body, "\n\n")
    {:ok, "text/plain", result}
  end

  # ---------------------------------------------------------------------------
  # Key transformation helpers
  # ---------------------------------------------------------------------------

  defp to_camel(key) do
    parts = String.split(key, ~r/[_\-]+/, trim: true)

    case parts do
      [] -> key
      [first | rest] -> first <> Enum.map_join(rest, &String.capitalize/1)
    end
  end

  defp to_kebab(key) do
    key
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1-\\2")
    |> String.replace("_", "-")
    |> String.downcase()
  end

  defp to_snake(key) do
    key
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.replace("-", "_")
    |> String.downcase()
  end

  # ---------------------------------------------------------------------------
  # Pure-string XML pretty-printer (no external parser required)
  # ---------------------------------------------------------------------------

  # `<[^<>]*>` rather than `<[^>]*>`: a run of "<" with one ">" at the end would
  # otherwise rescan to the end from every "<", quadratic in the input.
  @xml_token ~r/(<!\[CDATA\[[\s\S]*?\]\]>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<[^<>]*>|[^<]+)/

  # Nesting indents every line, so the output is quadratic in the depth.
  @xml_max_depth 100

  # An opener without a closer anywhere after it makes the lazy patterns above
  # scan to the end of the input once per opener. If the last opener of each
  # kind has a closer after it, every earlier one does too.
  @xml_pairs [{"<!--", "-->"}, {"<![CDATA[", "]]>"}, {"<?", "?>"}]

  defp unterminated?(input) do
    Enum.any?(@xml_pairs, fn {open, close} ->
      case :binary.matches(input, open) do
        [] ->
          false

        opens ->
          {last_open, _} = List.last(opens)

          case :binary.matches(input, close) do
            [] -> true
            closes -> elem(List.last(closes), 0) < last_open
          end
      end
    end)
  end

  defp pretty_xml(input) do
    if unterminated?(input), do: raise("unterminated markup")

    raw_tokens = Regex.scan(@xml_token, input, capture: :first) |> List.flatten()

    # Anything the tokenizer skipped (a stray "<") means the input is not XML.
    if Enum.sum(Enum.map(raw_tokens, &byte_size/1)) != byte_size(input),
      do: raise("stray markup")

    tokens =
      raw_tokens
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    has_element = Enum.any?(tokens, &String.starts_with?(&1, "<"))

    {lines, final_depth} =
      Enum.reduce(tokens, {[], 0}, fn token, {acc, depth} ->
        cond do
          String.starts_with?(token, "<?") ->
            {[token | acc], depth}

          String.starts_with?(token, "<!--") ->
            {[xmlpad(depth) <> token | acc], depth}

          String.starts_with?(token, "<![CDATA[") ->
            {[xmlpad(depth) <> token | acc], depth}

          Regex.match?(~r|^<[^/!?][^>]*/\s*>$|, token) ->
            {[xmlpad(depth) <> token | acc], depth}

          String.starts_with?(token, "</") ->
            d = max(0, depth - 1)
            {[xmlpad(d) <> token | acc], d}

          String.starts_with?(token, "<") ->
            if depth >= @xml_max_depth, do: raise("nested too deeply")
            {[xmlpad(depth) <> token | acc], depth + 1}

          true ->
            {[xmlpad(depth) <> token | acc], depth}
        end
      end)

    if not has_element or final_depth != 0 do
      :error
    else
      result = lines |> Enum.reverse() |> Enum.join("\n")

      formatted =
        if String.starts_with?(result, "<?xml") do
          result
        else
          ~s(<?xml version="1.0" encoding="UTF-8"?>\n) <> result
        end

      {:ok, formatted}
    end
  rescue
    _ -> :error
  end

  defp xmlpad(depth), do: String.duplicate("  ", depth)
end
