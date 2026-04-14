defmodule Leywn.Router do
  use Plug.Router

  plug Leywn.RequestLogger
  plug :set_server_header
  plug :match
  plug :dispatch

  get "/" do
    if System.get_env("LEYWN_ECHO_ON_HOME") == "true" do
      conn = Plug.Conn.fetch_query_params(conn)
      max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
      {body_info, conn} = Leywn.Body.read(conn, max_body)
      data = Leywn.Echo.build(conn, body_info)
      Leywn.Respond.send(conn, 200, data, root: "echo")
    else
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, home_html())
    end
  end

  get "/docs" do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, home_html())
  end

  get "/openapi.json" do
    port = Application.get_env(:leywn, :port, 4000)
    tls_port = Application.get_env(:leywn, :tls_port, 4443)

    spec =
      Application.app_dir(:leywn, "priv/openapi.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("servers", [
        %{"url" => "http://localhost:#{port}", "description" => "HTTP"},
        %{"url" => "https://localhost:#{tls_port}", "description" => "HTTPS / mTLS"}
      ])

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(spec))
  end

  match "/echo" do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    data = Leywn.Echo.build(conn, body_info)
    Leywn.Respond.send(conn, 200, data, root: "echo")
  end

  match "/echo/*_" do
    conn = Plug.Conn.fetch_query_params(conn)

    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)

    data = Leywn.Echo.build(conn, body_info)
    Leywn.Respond.send(conn, 200, data, root: "echo")
  end

  match "/anything" do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    data = Leywn.Echo.build(conn, body_info)
    Leywn.Respond.send(conn, 200, data, root: "echo")
  end

  match "/anything/*_" do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    data = Leywn.Echo.build(conn, body_info)
    Leywn.Respond.send(conn, 200, data, root: "echo")
  end

  get "/uuid" do
    Leywn.Respond.send(conn, 200, %{uuid: Leywn.Random.uuid()}, root: "uuid")
  end

  get "/guuid" do
    Leywn.Respond.send(conn, 200, %{guuid: Leywn.Random.guuid()}, root: "guuid")
  end

  get "/random" do
    data = %{
      int: Leywn.Random.random_int(),
      uint: Leywn.Random.random_uint(),
      uuid: Leywn.Random.uuid(),
      guuid: Leywn.Random.guuid(),
      lorem_ipsum: hd(Leywn.Random.lorem_ipsum(1))
    }
    Leywn.Respond.send(conn, 200, data, root: "random")
  end

  get "/random/int" do
    Leywn.Respond.send(conn, 200, %{value: Leywn.Random.random_int()}, root: "random")
  end

  get "/random/int/:lower/:upper" do
    with {lo, ""} <- Integer.parse(lower),
         {hi, ""} <- Integer.parse(upper),
         true <- lo <= hi do
      Leywn.Respond.send(conn, 200, %{value: Leywn.Random.random_int(lo, hi)}, root: "random")
    else
      _ ->
        Leywn.Respond.send(conn, 400,
          %{error: "invalid_range", lower: lower, upper: upper}, root: "error")
    end
  end

  get "/random/uint" do
    Leywn.Respond.send(conn, 200, %{value: Leywn.Random.random_uint()}, root: "random")
  end

  get "/random/lorem-ipsum" do
    paragraphs = Leywn.Random.lorem_ipsum(1)
    Leywn.Respond.send(conn, 200, %{paragraphs: paragraphs}, root: "lorem_ipsum")
  end

  get "/random/lorem-ipsum/:count" do
    case Integer.parse(count) do
      {n, ""} when n >= 1 ->
        paragraphs = Leywn.Random.lorem_ipsum(n)
        Leywn.Respond.send(conn, 200, %{paragraphs: paragraphs}, root: "lorem_ipsum")
      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_count", provided: count}, root: "error")
    end
  end

  match "/status/:code" do
    case Integer.parse(code) do
      {status, ""} when status in 100..599 ->
        if status in 100..199 or status in [204, 304] do
          Plug.Conn.send_resp(conn, status, "")
        else
          Leywn.Respond.send(conn, status, %{status: status}, root: "status")
        end

      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_status_code", provided: code}, root: "error")
    end
  end

  match "/auth/basic-auth" do
    Leywn.Auth.handle_basic(conn, "basic", "password")
  end

  match "/auth/basic-auth/:username/:password" do
    Leywn.Auth.handle_basic(conn, username, password)
  end

  match "/auth/api-key" do
    Leywn.Auth.handle_api_key(conn, "apikey", "my-key")
  end

  match "/auth/api-key/:header_name/:key_value" do
    Leywn.Auth.handle_api_key(conn, header_name, key_value)
  end

  match "/auth/jwt" do
    Leywn.Auth.handle_jwt(conn)
  end

  match "/auth/jwt/exchange" do
    Leywn.Auth.handle_jwt_exchange(conn)
  end

  match "/auth/mtls" do
    Leywn.Auth.handle_mtls(conn)
  end

  get "/auth/mtls/get-client-cert" do
    Leywn.Respond.send(conn, 200, %{
      cert_pem: Leywn.MTLS.client_cert_pem(),
      key_pem: Leywn.MTLS.client_key_pem()
    }, root: "client_cert")
  end

  get "/ip" do
    Leywn.Respond.send(conn, 200, Leywn.Info.ip_data(conn), root: "ip")
  end

  get "/ip/v4" do
    Leywn.Respond.send(conn, 200, Leywn.Info.ipv4_data(conn), root: "ip")
  end

  get "/ip/v6" do
    Leywn.Respond.send(conn, 200, Leywn.Info.ipv6_data(conn), root: "ip")
  end

  get "/date" do
    Leywn.Respond.send(conn, 200, Leywn.Info.date_utc(), root: "date")
  end

  get "/date/*timezone_parts" do
    tz = Enum.join(timezone_parts, "/")
    case Leywn.Info.date_tz(tz) do
      {:ok, data} ->
        Leywn.Respond.send(conn, 200, data, root: "date")
      {:error, :not_found} ->
        Leywn.Respond.send(conn, 404, %{error: "unknown_timezone", timezone: tz}, root: "error")
    end
  end

  get "/time" do
    Leywn.Respond.send(conn, 200, Leywn.Info.time_utc(), root: "time")
  end

  get "/time/*timezone_parts" do
    tz = Enum.join(timezone_parts, "/")
    case Leywn.Info.time_tz(tz) do
      {:ok, data} ->
        Leywn.Respond.send(conn, 200, data, root: "time")
      {:error, :not_found} ->
        Leywn.Respond.send(conn, 404, %{error: "unknown_timezone", timezone: tz}, root: "error")
    end
  end

  get "/image/color/:rgb" do
    handle_color_image(conn, rgb, 64, 64)
  end

  get "/image/color/:rgb/:width/:height" do
    with {w, ""} <- Integer.parse(width),
         {h, ""} <- Integer.parse(height) do
      handle_color_image(conn, rgb, w, h)
    else
      _ ->
        Leywn.Respond.send(conn, 400,
          %{error: "invalid_dimensions", width: width, height: height}, root: "error")
    end
  end

  get "/image/:type" do
    case Leywn.Logos.path_for(type) do
      {:ok, :file, path, content_type} ->
        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_file(200, path)

      {:ok, :inline, data, content_type} ->
        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_resp(200, data)

      {:error, reason} ->
        Leywn.Respond.send(conn, 400, %{error: reason}, root: "error")
    end
  end

  # ---- Format endpoints (POST only) ----------------------------------------

  post "/format/json",           do: handle_format(conn, &Leywn.Format.json/1)
  post "/format/yaml",           do: handle_format(conn, &Leywn.Format.yaml/1)
  post "/format/xml",            do: handle_format(conn, &Leywn.Format.xml/1)
  post "/format/camelCase",      do: handle_format(conn, &Leywn.Format.camel_case/1)
  post "/format/kebab-case",     do: handle_format(conn, &Leywn.Format.kebab_case/1)
  post "/format/snake-case",     do: handle_format(conn, &Leywn.Format.snake_case/1)
  post "/format/toUpper",        do: handle_format(conn, &Leywn.Format.to_upper/1)
  post "/format/toLower",        do: handle_format(conn, &Leywn.Format.to_lower/1)
  post "/format/collapse-lines", do: handle_format(conn, &Leywn.Format.collapse_lines/1)

  # ---- Codec endpoints (POST only) -----------------------------------------

  post "/encode/base64", do: handle_codec(conn, &Leywn.Codec.base64_encode/1)
  post "/decode/base64", do: handle_codec(conn, &Leywn.Codec.base64_decode/1)
  post "/encode/url",    do: handle_codec(conn, &Leywn.Codec.url_encode/1)
  post "/decode/url",    do: handle_codec(conn, &Leywn.Codec.url_decode/1)
  post "/encode/rot13",  do: handle_codec(conn, &Leywn.Codec.rot13/1)
  post "/decode/rot13",  do: handle_codec(conn, &Leywn.Codec.rot13/1)
  post "/decode/jwt",    do: handle_codec(conn, &Leywn.Codec.jwt_decode/1)

  match _ do
    Leywn.Respond.send(conn, 404, %{error: "not_found"}, root: "error")
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp handle_color_image(conn, rgb, width, height) do
    case Leywn.Logos.color_png(rgb, width, height) do
      {:ok, png} ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, png)

      {:error, reason} ->
        Leywn.Respond.send(conn, 400, %{error: reason}, root: "error")
    end
  end

  defp handle_format(conn, fun) do
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)

    case Plug.Conn.read_body(conn, length: max_body) do
      {:ok, body, conn} ->
        case fun.(body) do
          {:ok, content_type, result} ->
            conn
            |> Plug.Conn.put_resp_content_type(content_type)
            |> Plug.Conn.send_resp(200, result)

          {:error, msg} ->
            Leywn.Respond.send(conn, 422, %{error: msg}, root: "error")
        end

      {:more, _partial, conn} ->
        Leywn.Respond.send(conn, 413, %{error: "payload_too_large"}, root: "error")

      {:error, reason} ->
        Leywn.Respond.send(conn, 400, %{error: inspect(reason)}, root: "error")
    end
  end

  defp handle_codec(conn, fun), do: handle_format(conn, fun)

  defp set_server_header(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "server", "leywn")
  end

  defp home_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Leywn – Last Echo You Will Need</title>
      <link rel="icon" type="image/png" href="/image/png">
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        .leywn-header { background: #1a1a2e; color: #e0e0e0; padding: 1rem 3rem; display: flex; align-items: center; gap: 1.5rem; }
        .leywn-header span { font-size: 1.6rem; font-weight: 600; letter-spacing: -0.5px; }
        .leywn-hero { background: #1a1a2e; color: #e0e0e0; padding: 1.5rem 3rem 2.5rem; border-top: 1px solid rgba(255,255,255,0.08); }
        .leywn-hero p { margin: 0 0 0.6rem; opacity: 0.85; font-size: 1.05rem; }
        .leywn-hero code { background: rgba(255,255,255,0.12); padding: 0.15em 0.4em; border-radius: 3px; font-size: 0.9em; }
      </style>
    </head>
    <body>
      <div class="leywn-header">
        <img src="/image/png" alt="Leywn logo" style="height:56px;">
        <span>Last Echo You Will Need</span>
      </div>
      <div class="leywn-hero">
        <p>A complete selection of echo, auth, random, format, and codec endpoints — all in one lightweight, fast, highly customisable service.</p>
        <p>Configure everything with <code>LEYWN_xxx</code> environment variables. Set <code>LEYWN_ONLY_JSON=true</code> to disable XML content negotiation.</p>
      </div>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        SwaggerUIBundle({
          url: '/openapi.json',
          dom_id: '#swagger-ui',
          presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
          layout: 'BaseLayout',
          deepLinking: true,
          tryItOutEnabled: true
        });
      </script>
    </body>
    </html>
    """
  end
end
