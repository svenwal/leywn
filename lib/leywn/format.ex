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

  @doc "Convert a JSON body to YAML."
  def yaml(body) do
    with {:ok, data} <- Jason.decode(body) do
      {:ok, "application/yaml", Leywn.YAML.encode(data)}
    else
      {:error, _} -> {:error, "invalid JSON input"}
    end
  end

  @doc "Convert a JSON body to XML."
  def xml(body) do
    with {:ok, data} <- Jason.decode(body) do
      xml_str =
        XmlBuilder.document("root", Leywn.Respond.XML.to_elements(data))
        |> XmlBuilder.generate(format: :indent)

      {:ok, "application/xml", xml_str}
    else
      {:error, _} -> {:error, "invalid JSON input"}
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
end
