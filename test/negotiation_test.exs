defmodule Leywn.NegotiationTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @opts Leywn.Router.init([])

  defp get(path, headers \\ []) do
    conn(:get, path)
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> Leywn.Router.call(@opts)
  end

  defp content_type(conn), do: get_resp_header(conn, "content-type") |> hd()

  # ---- Default -----------------------------------------------------------------

  test "JSON is the default when no Accept header is sent" do
    conn = get("/health")
    assert content_type(conn) =~ "application/json"
    assert {:ok, _} = Jason.decode(conn.resp_body)
  end

  test "an Accept header we do not serve falls back to JSON" do
    for accept <- ["*/*", "text/html", "application/octet-stream"] do
      conn = get("/health", [{"accept", accept}])
      assert content_type(conn) =~ "application/json"
    end
  end

  # ---- XML ---------------------------------------------------------------------

  test "Accept: application/xml switches the representation" do
    conn = get("/health", [{"accept", "application/xml"}])
    assert content_type(conn) =~ "application/xml"
    assert conn.resp_body =~ "<health>"
    assert conn.resp_body =~ "<status>ok</status>"
  end

  test "text/xml and +xml suffixes are honoured too" do
    for accept <- ["text/xml", "application/soap+xml", "APPLICATION/XML"] do
      assert content_type(get("/health", [{"accept", accept}])) =~ "application/xml"
    end
  end

  test "XML responses carry a document root named after the endpoint" do
    assert get("/uuid", [{"accept", "application/xml"}]).resp_body =~ "<uuid>"
    assert get("/ip", [{"accept", "application/xml"}]).resp_body =~ "<ip>"
    assert get("/date", [{"accept", "application/xml"}]).resp_body =~ "<date>"
  end

  test "error responses are rendered as XML as well" do
    conn = get("/status/999", [{"accept", "application/xml"}])
    assert conn.status == 400
    assert content_type(conn) =~ "application/xml"
    assert conn.resp_body =~ "<error>"
  end

  test "lists are rendered as repeated <item> elements" do
    conn = get("/random/lorem-ipsum/2", [{"accept", "application/xml"}])
    assert conn.status == 200
    assert conn.resp_body =~ "<item>"
  end

  # ---- XML element-name sanitising ---------------------------------------------
  # Query-parameter and header names are attacker-controlled and become element
  # names. Unsanitised they would inject markup into the response document.

  test "markup in a query-parameter name cannot inject XML elements" do
    conn = get(~s(/echo?a><injected>pwned</injected><b=1), [{"accept", "application/xml"}])

    assert conn.status == 200
    refute conn.resp_body =~ "<injected>"
    refute conn.resp_body =~ "</injected>"
    assert conn.resp_body =~ "pwned"
  end

  test "a parameter name that cannot start an element name is prefixed" do
    conn = get("/echo?1leading=x", [{"accept", "application/xml"}])
    assert conn.status == 200
    assert conn.resp_body =~ "<_1leading>"
  end

  test "a header name with characters illegal in XML is sanitised" do
    conn = get("/echo", [{"accept", "application/xml"}, {"x$weird", "v"}])
    assert conn.status == 200
    assert conn.resp_body =~ "<x_weird>"
    refute conn.resp_body =~ "<x$weird>"
  end

  test "every element name emitted for hostile input is a legal XML name" do
    conn = get(~s(/echo?<bad>=1&2also=2&.dot=3&a b=4), [{"accept", "application/xml"}])

    element_names =
      Regex.scan(~r|<(/?)([^>]+)>|, conn.resp_body)
      |> Enum.map(fn [_, _, name] -> name end)
      |> Enum.reject(&String.starts_with?(&1, "?"))

    for name <- element_names do
      assert name =~ ~r/\A[A-Za-z_][A-Za-z0-9_.\-]*\z/, "illegal XML element name: #{name}"
    end
  end

  # ---- Pretty-printing ---------------------------------------------------------

  test "JSON responses are pretty-printed with two-space indentation" do
    conn = get("/echo?a=1")
    assert String.starts_with?(conn.resp_body, "{\n  \"")
    assert conn.resp_body =~ ~s(\n  "query_params": {\n    "a": "1"\n  })
    # Still exactly the same document, only laid out differently.
    assert conn.resp_body ==
             Jason.encode!(Jason.decode!(conn.resp_body, objects: :ordered_objects), pretty: true)
  end

  test "XML responses are pretty-printed with two-space indentation" do
    conn = get("/echo?a=1", [{"accept", "application/xml"}])

    assert conn.resp_body =~
             ~r/\A<\?xml [^>]+\?>\n<echo>\n  <.*\n  <query_params>\n    <a>1<\/a>\n  <\/query_params>\n/s

    assert String.ends_with?(conn.resp_body, "</echo>")
  end

  test "error bodies are pretty-printed too" do
    conn = get("/does-not-exist")
    assert conn.resp_body == ~s({\n  "error": "not_found"\n})

    conn = get("/does-not-exist", [{"accept", "application/xml"}])
    assert conn.resp_body =~ "<error>\n  <error>not_found</error>\n</error>"
  end

  test "the OpenAPI document is pretty-printed" do
    conn = get("/openapi.json")
    assert String.starts_with?(conn.resp_body, "{\n  \"")
    assert {:ok, %{"openapi" => _}} = Jason.decode(conn.resp_body)
  end

  test "the stream endpoint keeps one compact JSON object per line (NDJSON)" do
    lines = get("/stream/3").resp_body |> String.split("\n", trim: true)
    assert length(lines) == 3
    for line <- lines, do: assert({:ok, %{"line" => _}} = Jason.decode(line))
  end

  # ---- LEYWN_ONLY_JSON ---------------------------------------------------------

  describe "with LEYWN_ONLY_JSON=true" do
    setup do
      System.put_env("LEYWN_ONLY_JSON", "true")
      on_exit(fn -> System.delete_env("LEYWN_ONLY_JSON") end)
    end

    test "content negotiation is disabled and JSON is always returned" do
      conn = get("/health", [{"accept", "application/xml"}])
      assert content_type(conn) =~ "application/json"
      assert {:ok, _} = Jason.decode(conn.resp_body)
    end
  end
end
