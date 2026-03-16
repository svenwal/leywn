defmodule Leywn.Respond do
  import Plug.Conn

  def send(conn, status, data, opts \\ []) do
    root = Keyword.get(opts, :root, "response")

    case negotiate(conn) do
      :xml -> send_xml(conn, status, data, root)
      :json -> send_json(conn, status, data)
    end
  end

  defp negotiate(conn) do
    accept =
      conn
      |> get_req_header("accept")
      |> Enum.join(",")
      |> String.downcase()

    cond do
      accept == "" -> :json
      String.contains?(accept, "application/xml") -> :xml
      String.contains?(accept, "text/xml") -> :xml
      String.contains?(accept, "+xml") -> :xml
      true -> :json
    end
  end

  defp send_json(conn, status, data) do
    body = Jason.encode!(data)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_xml(conn, status, data, root) do
    xml =
      root
      |> XmlBuilder.document(Leywn.Respond.XML.to_elements(data))
      |> XmlBuilder.generate(format: :none)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(status, xml)
  end

  defmodule XML do
    def to_elements(%{} = map) do
      map
      |> Enum.sort_by(fn {k, _} -> key_name(k) end)
      |> Enum.map(fn {k, v} -> XmlBuilder.element(key_name(k), to_elements(v)) end)
    end

    def to_elements(list) when is_list(list) do
      case keywordish?(list) do
        true ->
          list
          |> Enum.map(fn {k, v} -> XmlBuilder.element(key_name(k), to_elements(v)) end)

        false ->
          Enum.map(list, fn v -> XmlBuilder.element("item", to_elements(v)) end)
      end
    end

    def to_elements(value) when is_binary(value), do: value
    def to_elements(value) when is_integer(value) or is_float(value), do: to_string(value)
    def to_elements(true), do: "true"
    def to_elements(false), do: "false"
    def to_elements(nil), do: ""

    def to_elements(value) when is_atom(value), do: Atom.to_string(value)

    def to_elements(value) do
      inspect(value)
    end

    defp keywordish?([]), do: false

    defp keywordish?(list) do
      Enum.all?(list, fn
        {k, _v} when is_binary(k) or is_atom(k) -> true
        _ -> false
      end)
    end

    defp key_name(k) when is_atom(k), do: Atom.to_string(k)
    defp key_name(k) when is_binary(k), do: k
    defp key_name(k), do: to_string(k)
  end
end

