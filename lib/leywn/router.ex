defmodule Leywn.Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/" do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, home_html())
  end

  get "/openapi.json" do
    spec = Application.app_dir(:leywn, "priv/openapi.json") |> File.read!()

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, spec)
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

  match "/auth/mtls" do
    Leywn.Auth.handle_mtls(conn)
  end

  get "/auth/mtls/get-client-cert" do
    Leywn.Respond.send(conn, 200, %{
      cert_pem: Leywn.MTLS.client_cert_pem(),
      key_pem: Leywn.MTLS.client_key_pem()
    }, root: "client_cert")
  end

  get "/image/:type" do
    case Leywn.Logos.path_for(type) do
      {:ok, path, content_type} ->
        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_file(200, path)

      {:error, reason} ->
        Leywn.Respond.send(conn, 400, %{error: reason}, root: "error")
    end
  end

  match _ do
    Leywn.Respond.send(conn, 404, %{error: "not_found"}, root: "error")
  end

  defp home_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Leywn – Last Echo You Will Need</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        .leywn-header { background: #ffffff ; color: #1a1a2e; padding: 1rem 3rem; }
        .leywn-hero { background: #1a1a2e; color: #e0e0e0; padding: 2.5rem 3rem; }
        .leywn-hero h1 { margin: 0 0 0.5rem; font-size: 2.2rem; letter-spacing: -0.5px; }
        .leywn-hero p { margin: 0 0 1rem; opacity: 0.8; font-size: 1.05rem; }
        .leywn-hero code { background: rgba(255,255,255,0.12); padding: 0.15em 0.4em; border-radius: 3px; font-size: 0.9em; }
        .leywn-hero ul { margin: 0.5rem 0 0; padding-left: 1.4rem; opacity: 0.75; line-height: 1.9; }
      </style>
    </head>
    <body>
      <div class="leywn-header">
        <img src="/image/png" alt="Leywn logo" style="height:72px;margin-bottom:1rem;display:block;">
      </div>
      <div class="leywn-hero">
        <h1>Leywn</h1>
        <p><em>Last Echo You Will Need</em> — an all-in-one demo backend for APIs and services.</p>
        <ul>
          <li><code>GET /echo</code> — echoes back all request details (headers, body, query params, …)</li>
          <li><code>ANY /echo/{path}</code> — same, for any sub-path</li>
          <li><code>ANY /status/{code}</code> — respond with any HTTP status code</li>
          <li><code>GET /image/{type}</code> — serve a demo image (<code>png</code>, <code>jpeg</code>, <code>gif</code>)</li>
          <li><code>ANY /auth/basic-auth</code> — Basic Auth (username: <code>basic</code>, password: <code>password</code>)</li>
          <li><code>ANY /auth/basic-auth/{user}/{pass}</code> — Basic Auth with custom credentials</li>
          <li><code>ANY /auth/api-key</code> — API key (header: <code>apikey: my-key</code>)</li>
          <li><code>ANY /auth/api-key/{header}/{value}</code> — API key with custom header and value</li>
          <li><code>ANY /auth/jwt</code> — Bearer JWT (validates structure, not signature)</li>
          <li><code>ANY /auth/mtls</code> — mTLS client certificate (HTTPS port 4443)</li>
          <li><code>GET /auth/mtls/get-client-cert</code> — download the generated client cert + key</li>
          <li><code>ANY /anything</code> — alias for <code>/echo</code></li>
          <li><code>GET /uuid</code> — random UUID v4</li>
          <li><code>GET /guuid</code> — random GUID (UUID v4 in curly braces)</li>
          <li><code>GET /random</code> — sample of all random values</li>
          <li><code>GET /random/int</code> — random integer in [-32000, 32000]</li>
          <li><code>GET /random/int/{lower}/{upper}</code> — random integer in custom range</li>
          <li><code>GET /random/uint</code> — random unsigned integer in [0, 65535]</li>
          <li><code>GET /random/lorem-ipsum</code> — one paragraph of Lorem Ipsum</li>
          <li><code>GET /random/lorem-ipsum/{n}</code> — up to 32 paragraphs of Lorem Ipsum</li>
        </ul>
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
