defmodule Leywn.Servers do
  @moduledoc """
  Builds the self-referencing URLs that go into OpenAPI `servers` arrays and the
  Insomnia collection.

  This lives outside the router because the main spec is no longer the only one:
  every mock renders its own, and two implementations of "which address did the
  caller actually reach us on" would drift apart.
  """

  @doc """
  The OpenAPI `servers` array for a request.

  This server always comes first so Swagger UI's "Try it out" calls back to the
  same origin the page was loaded from, whatever `LEYWN_EXTERNAL_*` says —
  otherwise the browser blocks it as mixed content or as a cross-origin request.
  """
  def servers(conn) do
    extra =
      [
        System.get_env("LEYWN_EXTERNAL_HTTP_URL") &&
          %{"url" => System.get_env("LEYWN_EXTERNAL_HTTP_URL"), "description" => "HTTP"},
        System.get_env("LEYWN_EXTERNAL_HTTPS_URL") &&
          %{"url" => System.get_env("LEYWN_EXTERNAL_HTTPS_URL"), "description" => "HTTPS / mTLS"}
      ]
      |> Enum.reject(&is_nil/1)

    [%{"url" => origin(conn), "description" => "This server"} | extra]
  end

  @doc """
  The origin the request arrived on, as `scheme://host[:port]`.
  """
  def origin(conn) do
    port = Application.get_env(:leywn, :port, 4000)
    scheme = if conn.scheme == :https, do: "https", else: "http"
    "#{scheme}://#{safe_host(conn, "localhost:#{port}")}"
  end

  @doc """
  The base URL to hand to a client, preferring an explicitly configured
  external URL.

  Used for the Insomnia collection, which has to name an address Insomnia can
  reach from outside the container.
  """
  def base_url(conn) do
    System.get_env("LEYWN_EXTERNAL_HTTPS_URL") ||
      System.get_env("LEYWN_EXTERNAL_HTTP_URL") ||
      origin(conn)
  end

  # conn.host / conn.port rather than the Host header, because HTTP/2 — which
  # the HTTPS listener negotiates via ALPN — has no Host header at all. Plug
  # populates conn.host/conn.port from :authority in that case, so reading the
  # raw header made every HTTPS URL fall back to the plain-HTTP default port.
  #
  # The host is still sanitised: it ends up in URLs and JSON, so anything with
  # path separators, whitespace or other injection-capable characters is
  # rejected.
  defp safe_host(conn, default) do
    host = conn.host || ""

    if Regex.match?(~r/\A[a-zA-Z0-9._\-]+\z/, host) do
      host <> port_suffix(conn.scheme, conn.port)
    else
      default
    end
  end

  defp port_suffix(:https, 443), do: ""
  defp port_suffix(:http, 80), do: ""
  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"
end
