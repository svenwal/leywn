defmodule Leywn.Format do
  @moduledoc """
  POST body format / prettify transformations.
  Each function returns {:ok, content_type, body} or {:error, message}.
  """

  @doc "Pretty-print a JSON body."
  def json(body) do
    with {:ok, data} <- Jason.decode(body) do
      {:ok, "application/json", Jason.encode!(data, pretty: true)}
    else
      {:error, _} -> {:error, "invalid JSON input"}
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
          {:ok, data} -> {:ok, "application/yaml", Leywn.YAML.encode(data)}
          {:error, _} -> {:error, "invalid YAML input"}
        end
      rescue
        _ -> {:error, "invalid YAML input"}
      catch
        _, _ -> {:error, "invalid YAML input"}
      end
    end
  end

  @doc "Pretty-format an XML body with consistent 2-space indentation."
  def xml(body) do
    case pretty_xml(String.trim(body)) do
      {:ok, formatted} -> {:ok, "application/xml", formatted}
      :error -> {:error, "invalid XML input"}
    end
  end

  @doc "Recursively convert all JSON keys to camelCase."
  def camel_case(body) do
    with {:ok, data} <- Jason.decode(body) do
      {:ok, "application/json", Jason.encode!(transform_keys(data, &to_camel/1), pretty: true)}
    else
      {:error, _} -> {:error, "invalid JSON input"}
    end
  end

  @doc "Recursively convert all JSON keys to kebab-case."
  def kebab_case(body) do
    with {:ok, data} <- Jason.decode(body) do
      {:ok, "application/json", Jason.encode!(transform_keys(data, &to_kebab/1), pretty: true)}
    else
      {:error, _} -> {:error, "invalid JSON input"}
    end
  end

  @doc "Recursively convert all JSON keys to snake_case."
  def snake_case(body) do
    with {:ok, data} <- Jason.decode(body) do
      {:ok, "application/json", Jason.encode!(transform_keys(data, &to_snake/1), pretty: true)}
    else
      {:error, _} -> {:error, "invalid JSON input"}
    end
  end

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

  defp transform_keys(map, fun) when is_map(map) do
    Map.new(map, fn {k, v} -> {fun.(to_string(k)), transform_keys(v, fun)} end)
  end

  defp transform_keys(list, fun) when is_list(list) do
    Enum.map(list, &transform_keys(&1, fun))
  end

  defp transform_keys(value, _fun), do: value

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

  @xml_token ~r/(<!\[CDATA\[[\s\S]*?\]\]>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<[^>]*>|[^<]+)/

  defp pretty_xml(input) do
    tokens =
      @xml_token
      |> Regex.scan(input, capture: :first)
      |> List.flatten()
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
