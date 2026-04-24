defmodule Leywn.Router do
  use Plug.Router

  plug(Leywn.CORS)
  plug(Leywn.RequestLogger)
  plug(:set_server_header)
  plug(:match)
  plug(:dispatch)

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
      |> Plug.Conn.send_resp(200, home_html(collection_url(conn)))
    end
  end

  get "/docs" do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, home_html(collection_url(conn)))
  end

  get "/openapi.json" do
    port = Application.get_env(:leywn, :port, 4000)
    tls_port = Application.get_env(:leywn, :tls_port, 4443)

    # Always put "this server" first so Swagger UI's "Try it out" calls back to the
    # same origin the page was loaded from. This prevents mixed-content blocks and
    # CORS errors regardless of how LEYWN_EXTERNAL_* URLs are configured.
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = safe_host(conn, "localhost:#{port}")
    this_server = %{"url" => "#{scheme}://#{host}", "description" => "This server"}

    extra_servers =
      [
        System.get_env("LEYWN_EXTERNAL_HTTP_URL") &&
          %{"url" => System.get_env("LEYWN_EXTERNAL_HTTP_URL"), "description" => "HTTP"},
        System.get_env("LEYWN_EXTERNAL_HTTPS_URL") &&
          %{"url" => System.get_env("LEYWN_EXTERNAL_HTTPS_URL"), "description" => "HTTPS / mTLS"}
      ]
      |> Enum.reject(&is_nil/1)

    servers = [this_server | extra_servers]

    spec =
      Application.app_dir(:leywn, "priv/openapi.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("servers", servers)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(spec))
  end

  # ---- Insomnia collection ---------------------------------------------------

  get "/request-collection" do
    port = Application.get_env(:leywn, :port, 4000)
    collection = Leywn.InsomniaCollection.build(port)

    conn
    |> Plug.Conn.put_resp_header(
      "content-disposition",
      ~s(attachment; filename="leywn.insomnia.json")
    )
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(collection, pretty: true))
  end

  # ---- Health ----------------------------------------------------------------

  get "/health" do
    started_at = Application.get_env(:leywn, :started_at, System.monotonic_time(:second))
    uptime = System.monotonic_time(:second) - started_at

    Leywn.Respond.send(
      conn,
      200,
      %{
        status: "ok",
        version: Application.spec(:leywn, :vsn) |> to_string(),
        uptime_seconds: uptime
      },
      root: "health"
    )
  end

  # ---- Echo ------------------------------------------------------------------

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

  # ---- Chaos Engineering -----------------------------------------------------

  match "/chaos-engineering" do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    echo_data = Leywn.Echo.build(conn, body_info)
    params = Leywn.Chaos.from_headers(conn)
    Leywn.Chaos.apply_chaos(conn, params, echo_data)
  end

  match "/chaos-engineering/:error_pct/:mangled_pct/:latency_pct/:max_latency" do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    echo_data = Leywn.Echo.build(conn, body_info)

    case Leywn.Chaos.from_path(error_pct, mangled_pct, latency_pct, max_latency) do
      {:ok, params} ->
        Leywn.Chaos.apply_chaos(conn, params, echo_data)

      {:error, field, msg} ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_chaos_params", field: field, detail: msg},
          root: "error"
        )
    end
  end

  # ---- Delay -----------------------------------------------------------------

  match "/delay/:ms" do
    case Integer.parse(ms) do
      {delay, ""} when delay >= 0 and delay <= 30_000 ->
        :timer.sleep(delay)
        Leywn.Respond.send(conn, 200, %{requested_ms: delay, delayed_ms: delay}, root: "delay")

      {delay, ""} when delay > 30_000 ->
        Leywn.Respond.send(
          conn,
          400,
          %{error: "delay_too_large", maximum_ms: 30_000, provided_ms: delay},
          root: "error"
        )

      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_delay", provided: ms}, root: "error")
    end
  end

  # ---- Stream ----------------------------------------------------------------

  get "/stream/:n" do
    case Integer.parse(n) do
      {count, ""} when count >= 1 and count <= 100 ->
        conn =
          conn
          |> Plug.Conn.put_resp_content_type("application/x-ndjson")
          |> Plug.Conn.send_chunked(200)

        Enum.reduce_while(1..count, conn, fn i, conn ->
          line =
            Jason.encode!(%{
              line: i,
              total: count,
              timestamp_unix_ms: System.os_time(:millisecond)
            })

          case Plug.Conn.chunk(conn, line <> "\n") do
            {:ok, conn} -> {:cont, conn}
            {:error, _} -> {:halt, conn}
          end
        end)

      {count, ""} when count > 100 ->
        Leywn.Respond.send(conn, 400, %{error: "count_too_large", maximum: 100, provided: count},
          root: "error"
        )

      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_count", provided: n}, root: "error")
    end
  end

  # ---- UUID / GUID -----------------------------------------------------------

  get "/uuid" do
    Leywn.Respond.send(conn, 200, %{uuid: Leywn.Random.uuid()}, root: "uuid")
  end

  get "/guuid" do
    Leywn.Respond.send(conn, 200, %{guuid: Leywn.Random.guuid()}, root: "guuid")
  end

  # ---- Random ----------------------------------------------------------------

  get "/random" do
    data = %{
      int: Leywn.Random.random_int(),
      uint: Leywn.Random.random_uint(),
      uuid: Leywn.Random.uuid(),
      guuid: Leywn.Random.guuid(),
      lorem_ipsum: hd(Leywn.Random.lorem_ipsum(1)),
      name: Leywn.Random.random_name(),
      email: Leywn.Random.random_email(),
      color: Leywn.Random.random_color()
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
        Leywn.Respond.send(conn, 400, %{error: "invalid_range", lower: lower, upper: upper},
          root: "error"
        )
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
      {n, ""} when n >= 1 and n <= 32 ->
        paragraphs = Leywn.Random.lorem_ipsum(n)
        Leywn.Respond.send(conn, 200, %{paragraphs: paragraphs}, root: "lorem_ipsum")

      {n, ""} when n > 32 ->
        Leywn.Respond.send(conn, 400, %{error: "count_too_large", maximum: 32, provided: n},
          root: "error"
        )

      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_count", provided: count}, root: "error")
    end
  end

  get "/random/name" do
    Leywn.Respond.send(conn, 200, %{name: Leywn.Random.random_name()}, root: "random")
  end

  get "/random/email" do
    Leywn.Respond.send(conn, 200, %{email: Leywn.Random.random_email()}, root: "random")
  end

  get "/random/color" do
    Leywn.Respond.send(conn, 200, Leywn.Random.random_color(), root: "random")
  end

  # ---- Status ----------------------------------------------------------------

  match "/status/:code" do
    case Integer.parse(code) do
      {status, ""} when status in 100..599 ->
        if status in 100..199 or status in [204, 304] do
          Plug.Conn.send_resp(conn, status, "")
        else
          Leywn.Respond.send(conn, status, %{status: status}, root: "status")
        end

      _ ->
        Leywn.Respond.send(conn, 400, %{error: "invalid_status_code", provided: code},
          root: "error"
        )
    end
  end

  # ---- Auth ------------------------------------------------------------------

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
    Leywn.Respond.send(
      conn,
      200,
      %{
        cert_pem: Leywn.MTLS.client_cert_pem(),
        key_pem: Leywn.MTLS.client_key_pem()
      },
      root: "client_cert"
    )
  end

  # ---- Info ------------------------------------------------------------------

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

  # ---- Images ----------------------------------------------------------------

  get "/image/color/:rgb" do
    handle_color_image(conn, rgb, 64, 64)
  end

  get "/image/color/:rgb/:width/:height" do
    with {w, ""} <- Integer.parse(width),
         {h, ""} <- Integer.parse(height) do
      handle_color_image(conn, rgb, w, h)
    else
      _ ->
        Leywn.Respond.send(
          conn,
          400,
          %{error: "invalid_dimensions", width: width, height: height},
          root: "error"
        )
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

  post("/format/json", do: handle_format(conn, &Leywn.Format.json/1))
  post("/format/yaml", do: handle_format(conn, &Leywn.Format.yaml/1))
  post("/format/xml", do: handle_format(conn, &Leywn.Format.xml/1))
  post("/format/camelCase", do: handle_format(conn, &Leywn.Format.camel_case/1))
  post("/format/kebab-case", do: handle_format(conn, &Leywn.Format.kebab_case/1))
  post("/format/snake_case", do: handle_format(conn, &Leywn.Format.snake_case/1))
  post("/format/toUpper", do: handle_format(conn, &Leywn.Format.to_upper/1))
  post("/format/toLower", do: handle_format(conn, &Leywn.Format.to_lower/1))
  post("/format/collapse-lines", do: handle_format(conn, &Leywn.Format.collapse_lines/1))

  # ---- Codec endpoints (POST only) -----------------------------------------

  post("/encode/base64", do: handle_codec(conn, &Leywn.Codec.base64_encode/1))
  post("/decode/base64", do: handle_codec(conn, &Leywn.Codec.base64_decode/1))
  post("/encode/url", do: handle_codec(conn, &Leywn.Codec.url_encode/1))
  post("/decode/url", do: handle_codec(conn, &Leywn.Codec.url_decode/1))
  post("/encode/rot13", do: handle_codec(conn, &Leywn.Codec.rot13/1))
  post("/decode/rot13", do: handle_codec(conn, &Leywn.Codec.rot13/1))
  post("/decode/jwt", do: handle_codec(conn, &Leywn.Codec.jwt_decode/1))
  post("/encode/hex", do: handle_codec(conn, &Leywn.Codec.hex_encode/1))
  post("/decode/hex", do: handle_codec(conn, &Leywn.Codec.hex_decode/1))

  # ---- Hash endpoints (POST only) ------------------------------------------

  post("/hash/sha256", do: handle_codec(conn, &Leywn.Hash.sha256/1))
  post("/hash/md5", do: handle_codec(conn, &Leywn.Hash.md5/1))

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

      {:error, _reason} ->
        Leywn.Respond.send(conn, 400, %{error: "could_not_read_body"}, root: "error")
    end
  end

  defp handle_codec(conn, fun), do: handle_format(conn, fun)

  defp set_server_header(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "server", "leywn")
  end

  # Sanitise the Host header before embedding it in URLs or JSON responses.
  # Accepts only hostname[:port] — rejects anything containing path separators,
  # whitespace, or other characters that could enable header/URL injection.
  defp safe_host(conn, default) do
    raw = Plug.Conn.get_req_header(conn, "host") |> List.first() || default
    if Regex.match?(~r/\A[a-zA-Z0-9._\-]+(:\d+)?\z/, raw), do: raw, else: default
  end

  defp collection_url(conn) do
    port = Application.get_env(:leywn, :port, 4000)
    # Prefer HTTPS external URL, then HTTP external URL, then derive from the request.
    # The Insomnia button must point to a URL Insomnia can actually fetch — an HTTP URL
    # on an HTTPS-only server will fail. Request-derived URL always matches the scheme
    # the user is actually on.
    base =
      System.get_env("LEYWN_EXTERNAL_HTTPS_URL") ||
        System.get_env("LEYWN_EXTERNAL_HTTP_URL") ||
        (fn ->
           scheme = if conn.scheme == :https, do: "https", else: "http"
           host = safe_host(conn, "localhost:#{port}")
           "#{scheme}://#{host}"
         end).()

    base <> "/request-collection"
  end

  defp home_html(collection_url) do
    encoded_url = URI.encode_www_form(collection_url)
    insomnia_href = "https://insomnia.rest/run/?label=Leywn&uri=#{encoded_url}"

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
        .leywn-header .leywn-actions { margin-left: auto; display: flex; align-items: center; gap: 0.75rem; }
        .leywn-btn { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.4rem 0.85rem; border-radius: 6px; font-size: 0.85rem; font-weight: 600; text-decoration: none; white-space: nowrap; }
        .leywn-btn-gh { background: #24292f; color: #fff; border: 1px solid rgba(255,255,255,0.15); }
        .leywn-btn-dh { background: #1d63ed; color: #fff; border: 1px solid rgba(255,255,255,0.15); }
        .leywn-btn:hover { opacity: 0.85; }
        .leywn-hero { background: #1a1a2e; color: #e0e0e0; padding: 1.5rem 3rem 2.5rem; border-top: 1px solid rgba(255,255,255,0.08); }
        .leywn-hero p { margin: 0 0 0.6rem; opacity: 0.85; font-size: 1.05rem; }
        .leywn-hero code { background: rgba(255,255,255,0.12); padding: 0.15em 0.4em; border-radius: 3px; font-size: 0.9em; }
      </style>
    </head>
    <body>
      <div class="leywn-header">
        <img src="/image/png" alt="Leywn logo" style="height:56px;">
        <span>Last Echo You Will Need</span>
        <div class="leywn-actions">
          <a href="https://github.com/svenwal/leywn" target="_blank" rel="noopener" class="leywn-btn leywn-btn-gh">
            <svg height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.65 7.65 0 012-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
            GitHub
          </a>
          <a href="https://hub.docker.com/r/svenwal/leywn" target="_blank" rel="noopener" class="leywn-btn leywn-btn-dh">
            <svg height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M13.983 11.078h2.119a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186h-2.119a.185.185 0 00-.185.185v1.888c0 .102.083.185.185.185m-2.954-5.43h2.118a.186.186 0 00.186-.186V3.574a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m0 2.716h2.118a.187.187 0 00.186-.186V6.29a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.185.185v1.887c0 .102.082.185.185.186m-2.93 0h2.12a.186.186 0 00.184-.186V6.29a.185.185 0 00-.185-.185H8.1a.185.185 0 00-.185.185v1.887c0 .102.083.185.185.186m-2.964 0h2.119a.186.186 0 00.185-.186V6.29a.185.185 0 00-.185-.185H5.136a.186.186 0 00-.186.185v1.887c0 .102.084.185.186.186m5.893 2.715h2.118a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m-2.93 0h2.12a.185.185 0 00.184-.185V9.006a.185.185 0 00-.184-.186h-2.12a.185.185 0 00-.184.185v1.888c0 .102.083.185.185.185m-2.964 0h2.119a.185.185 0 00.185-.185V9.006a.185.185 0 00-.185-.186h-2.12a.186.186 0 00-.184.185v1.888c0 .102.083.185.185.185m-2.92 0h2.12a.186.186 0 00.184-.185V9.006a.185.185 0 00-.184-.186h-2.12a.185.185 0 00-.185.185v1.888c0 .102.082.185.184.185M23.763 9.89c-.065-.051-.672-.51-1.954-.51-.338.001-.676.03-1.01.087-.248-1.7-1.653-2.53-1.716-2.566l-.344-.199-.226.327c-.284.438-.49.922-.612 1.43-.23.97-.09 1.882.403 2.661-.595.332-1.55.413-1.744.42H.751a.751.751 0 00-.75.748 11.376 11.376 0 00.692 4.062c.545 1.428 1.355 2.48 2.41 3.124 1.18.723 3.1 1.137 5.275 1.137.983.003 1.963-.086 2.93-.266a12.248 12.248 0 003.823-1.389c.98-.567 1.86-1.288 2.61-2.136 1.252-1.418 1.998-2.997 2.553-4.4h.221c1.372 0 2.215-.549 2.68-1.009.309-.293.55-.65.707-1.046l.098-.288z"/></svg>
            Docker Hub
          </a>
          <a href="#{insomnia_href}" target="_blank" rel="noopener">
            <img src="https://insomnia.rest/images/run.svg" alt="Run in Insomnia">
          </a>
        </div>
      </div>
      <div class="leywn-hero">
        <p>Leywn is the last demo backend you will ever need. Whether you are building a new API client, stress-testing a retry strategy, demonstrating an integration, or just need a quick echo server for a workshop — Leywn has you covered with a single <code>docker run</code>.</p>
        <p>Every endpoint is purposefully designed: mirror your requests with <code>/echo</code>, simulate network latency with <code>/delay</code>, stream chunked responses with <code>/stream</code>, test all your auth flows, generate random data, hash and encode payloads, and more. Zero dependencies to manage, zero state to worry about, and everything tunable via <code>LEYWN_</code> environment variables.</p>
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
          tryItOutEnabled: true,
          docExpansion: 'none'
        });
      </script>
    </body>
    </html>
    """
  end
end
