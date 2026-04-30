defmodule Leywn.InsomniaCollection do
  @moduledoc "Generates an Insomnia v4 export collection covering all Leywn endpoints."

  @jwt_example "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" <>
                 ".eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IkFsaWNlIiwiaWF0IjoxNzAwMDAwMDAwfQ" <>
                 ".fakesignature"

  def build(port) do
    base_url =
      System.get_env("LEYWN_EXTERNAL_HTTPS_URL") ||
        System.get_env("LEYWN_EXTERNAL_HTTP_URL") ||
        "http://localhost:#{port}"

    %{
      "_type" => "export",
      "__export_format" => 4,
      "__export_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "__export_source" => "leywn",
      "resources" => resources(base_url)
    }
  end

  # ---------------------------------------------------------------------------
  # Top-level resources
  # ---------------------------------------------------------------------------

  defp resources(base_url) do
    [workspace(), environment(base_url)] ++
      folder_utility() ++
      folder_echo() ++
      folder_chaos() ++
      folder_auth() ++
      folder_random() ++
      folder_info() ++
      folder_format() ++
      folder_codec() ++
      folder_hash()
  end

  defp workspace do
    %{
      "_id" => "wrk_leywn",
      "_type" => "workspace",
      "parentId" => nil,
      "name" => "Leywn",
      "description" => "Last Echo You Will Need — complete request collection"
    }
  end

  defp environment(base_url) do
    %{
      "_id" => "env_leywn_base",
      "_type" => "environment",
      "parentId" => "wrk_leywn",
      "name" => "Base Environment",
      "data" => %{"base_url" => base_url}
    }
  end

  # ---------------------------------------------------------------------------
  # Utility
  # ---------------------------------------------------------------------------

  defp folder_utility do
    [folder("fld_utility", "Utility")] ++
      [
        req("req_health", "GET /health", "GET", "/health", "fld_utility"),
        req("req_delay_500", "GET /delay/500", "GET", "/delay/500", "fld_utility",
          description: "Wait 500 ms before responding"
        ),
        req("req_delay_0", "GET /delay/0", "GET", "/delay/0", "fld_utility",
          description: "Respond immediately (0 ms delay)"
        ),
        req("req_stream_5", "GET /stream/5", "GET", "/stream/5", "fld_utility",
          description: "Stream 5 ndjson lines"
        ),
        req("req_status_200", "GET /status/200", "GET", "/status/200", "fld_utility"),
        req("req_status_404", "GET /status/404", "GET", "/status/404", "fld_utility"),
        req("req_status_418", "GET /status/418", "GET", "/status/418", "fld_utility",
          description: "I'm a teapot"
        ),
        req("req_status_500", "GET /status/500", "GET", "/status/500", "fld_utility"),
        req("req_img_png", "GET /image/png", "GET", "/image/png", "fld_utility"),
        req("req_img_jpeg", "GET /image/jpeg", "GET", "/image/jpeg", "fld_utility"),
        req("req_img_gif", "GET /image/gif", "GET", "/image/gif", "fld_utility"),
        req("req_img_svg", "GET /image/svg", "GET", "/image/svg", "fld_utility"),
        req(
          "req_img_color",
          "GET /image/color/1a2b3c",
          "GET",
          "/image/color/1a2b3c",
          "fld_utility"
        ),
        req(
          "req_img_color_sz",
          "GET /image/color/ff0000/200/100",
          "GET",
          "/image/color/ff0000/200/100",
          "fld_utility"
        ),
        req(
          "req_collection",
          "GET /request-collection",
          "GET",
          "/request-collection",
          "fld_utility",
          description: "Download this Insomnia collection"
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Echo
  # ---------------------------------------------------------------------------

  defp folder_echo do
    [folder("fld_echo", "Echo")] ++
      [
        req("req_echo_get", "GET /echo", "GET", "/echo", "fld_echo"),
        req("req_echo_post", "POST /echo (JSON body)", "POST", "/echo", "fld_echo",
          headers: [content_type("application/json")],
          body: json_body(~s({"hello": "world"}))
        ),
        req("req_echo_put", "PUT /echo", "PUT", "/echo", "fld_echo"),
        req("req_echo_patch", "PATCH /echo", "PATCH", "/echo", "fld_echo"),
        req("req_echo_del", "DELETE /echo", "DELETE", "/echo", "fld_echo"),
        req("req_echo_sub", "GET /echo/some/sub/path", "GET", "/echo/some/sub/path", "fld_echo"),
        req("req_anything", "GET /anything", "GET", "/anything", "fld_echo"),
        req("req_anything_s", "GET /anything/foo/bar", "GET", "/anything/foo/bar", "fld_echo")
      ]
  end

  # ---------------------------------------------------------------------------
  # Chaos Engineering
  # ---------------------------------------------------------------------------

  defp folder_chaos do
    [folder("fld_chaos", "Chaos Engineering")] ++
      [
        req(
          "req_chaos_default",
          "ANY /chaos-engineering (defaults)",
          "GET",
          "/chaos-engineering",
          "fld_chaos",
          description: "Defaults: 10% error, 10% mangled, 20% latency, max 2000 ms"
        ),
        req(
          "req_chaos_headers",
          "ANY /chaos-engineering (via headers)",
          "GET",
          "/chaos-engineering",
          "fld_chaos",
          headers: [
            header("x-chaos-error-percentage", "25"),
            header("x-chaos-mangled-percentage", "25"),
            header("x-chaos-latency-percentage", "50"),
            header("x-chaos-maximum-latency", "3000")
          ],
          description: "Chaos params supplied as X-Chaos-* headers"
        ),
        req(
          "req_chaos_path",
          "ANY /chaos-engineering/25/25/50/3000",
          "GET",
          "/chaos-engineering/25/25/50/3000",
          "fld_chaos",
          description: "error 25%, mangled 25%, latency 50%, max 3000 ms"
        ),
        req(
          "req_chaos_high",
          "ANY /chaos-engineering/50/50/100/5000",
          "GET",
          "/chaos-engineering/50/50/100/5000",
          "fld_chaos",
          description: "High chaos: 50% error, 50% mangled, always latency up to 5 s"
        ),
        req(
          "req_chaos_latency",
          "ANY /chaos-engineering/0/0/100/2000",
          "GET",
          "/chaos-engineering/0/0/100/2000",
          "fld_chaos",
          description: "Latency only — no errors or mangling"
        ),
        req(
          "req_chaos_errors",
          "ANY /chaos-engineering/100/0/0/0",
          "GET",
          "/chaos-engineering/100/0/0/0",
          "fld_chaos",
          description: "Always inject an error code — no latency or mangling"
        ),
        req(
          "req_chaos_mangled",
          "ANY /chaos-engineering/0/100/0/0",
          "GET",
          "/chaos-engineering/0/100/0/0",
          "fld_chaos",
          description: "Always return a mangled response — no latency or errors"
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Auth
  # ---------------------------------------------------------------------------

  defp folder_auth do
    [folder("fld_auth", "Auth")] ++
      [
        req(
          "req_basic_default",
          "GET /auth/basic-auth (default)",
          "GET",
          "/auth/basic-auth",
          "fld_auth",
          auth: basic_auth("basic", "password"),
          description: "Default credentials: basic / password"
        ),
        req(
          "req_basic_wrong",
          "GET /auth/basic-auth (wrong)",
          "GET",
          "/auth/basic-auth",
          "fld_auth",
          auth: basic_auth("wrong", "wrong"),
          description: "Wrong credentials — expect 401"
        ),
        req(
          "req_basic_custom",
          "GET /auth/basic-auth/alice/s3cr3t",
          "GET",
          "/auth/basic-auth/alice/s3cr3t",
          "fld_auth",
          auth: basic_auth("alice", "s3cr3t"),
          description: "Custom credentials in path"
        ),
        req(
          "req_apikey_default",
          "GET /auth/api-key (default)",
          "GET",
          "/auth/api-key",
          "fld_auth",
          headers: [header("apikey", "my-key")],
          description: "Default header: apikey: my-key"
        ),
        req(
          "req_apikey_missing",
          "GET /auth/api-key (missing key)",
          "GET",
          "/auth/api-key",
          "fld_auth",
          description: "No key header — expect 401"
        ),
        req(
          "req_apikey_custom",
          "GET /auth/api-key/X-Token/abc123",
          "GET",
          "/auth/api-key/X-Token/abc123",
          "fld_auth",
          headers: [header("x-token", "abc123")],
          description: "Custom header name and value"
        ),
        req("req_jwt", "GET /auth/jwt", "GET", "/auth/jwt", "fld_auth",
          headers: [bearer(@jwt_example)],
          description: "Bearer JWT — structure validated, signature ignored"
        ),
        req(
          "req_jwt_exchange",
          "ANY /auth/jwt/exchange (Bearer)",
          "GET",
          "/auth/jwt/exchange",
          "fld_auth",
          headers: [bearer(@jwt_example)],
          description: "Exchange incoming JWT for a Leywn-signed HS256 token (Bearer variant)"
        ),
        req(
          "req_jwt_exchange_rfc8693",
          "POST /auth/jwt/exchange (RFC 8693)",
          "POST",
          "/auth/jwt/exchange",
          "fld_auth",
          headers: [content_type("application/x-www-form-urlencoded")],
          body:
            form_body([
              {"grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"},
              {"subject_token", @jwt_example},
              {"subject_token_type", "urn:ietf:params:oauth:token-type:jwt"},
              {"audience", "my-service"},
              {"scope", "read write"}
            ]),
          description:
            "RFC 8693 token exchange — POST application/x-www-form-urlencoded; audience and scope are optional"
        ),
        req(
          "req_mtls_getcert",
          "GET /auth/mtls/get-client-cert",
          "GET",
          "/auth/mtls/get-client-cert",
          "fld_auth",
          description: "Download the demo mTLS client certificate and key"
        ),
        req("req_mtls", "GET /auth/mtls (HTTPS port)", "GET", "/auth/mtls", "fld_auth",
          description: "Requires mTLS client cert — use HTTPS port (4443) with downloaded cert"
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Random
  # ---------------------------------------------------------------------------

  defp folder_random do
    [folder("fld_random", "Random")] ++
      [
        req("req_random_all", "GET /random", "GET", "/random", "fld_random",
          description: "One of each random type"
        ),
        req("req_random_int", "GET /random/int", "GET", "/random/int", "fld_random"),
        req(
          "req_random_int_r",
          "GET /random/int/-100/100",
          "GET",
          "/random/int/-100/100",
          "fld_random"
        ),
        req("req_random_uint", "GET /random/uint", "GET", "/random/uint", "fld_random"),
        req(
          "req_random_lorem",
          "GET /random/lorem-ipsum",
          "GET",
          "/random/lorem-ipsum",
          "fld_random"
        ),
        req(
          "req_random_lorem3",
          "GET /random/lorem-ipsum/3",
          "GET",
          "/random/lorem-ipsum/3",
          "fld_random"
        ),
        req("req_random_name", "GET /random/name", "GET", "/random/name", "fld_random"),
        req("req_random_email", "GET /random/email", "GET", "/random/email", "fld_random"),
        req("req_random_color", "GET /random/color", "GET", "/random/color", "fld_random"),
        req("req_uuid", "GET /uuid", "GET", "/uuid", "fld_random"),
        req("req_guuid", "GET /guuid", "GET", "/guuid", "fld_random")
      ]
  end

  # ---------------------------------------------------------------------------
  # Info
  # ---------------------------------------------------------------------------

  defp folder_info do
    [folder("fld_info", "Info")] ++
      [
        req("req_ip", "GET /ip", "GET", "/ip", "fld_info"),
        req("req_ip_v4", "GET /ip/v4", "GET", "/ip/v4", "fld_info"),
        req("req_ip_v6", "GET /ip/v6", "GET", "/ip/v6", "fld_info"),
        req("req_date", "GET /date", "GET", "/date", "fld_info"),
        req(
          "req_date_tz",
          "GET /date/America/New_York",
          "GET",
          "/date/America/New_York",
          "fld_info"
        ),
        req("req_time", "GET /time", "GET", "/time", "fld_info"),
        req("req_time_tz", "GET /time/Europe/Berlin", "GET", "/time/Europe/Berlin", "fld_info")
      ]
  end

  # ---------------------------------------------------------------------------
  # Format
  # ---------------------------------------------------------------------------

  defp folder_format do
    [folder("fld_format", "Format")] ++
      [
        req("req_fmt_json", "POST /format/json", "POST", "/format/json", "fld_format",
          headers: [content_type("application/json")],
          body: json_body(~s({"b":2,"a":1,"nested":{"z":26,"a":1}}))
        ),
        req("req_fmt_yaml", "POST /format/yaml", "POST", "/format/yaml", "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("person:\n    name: Bob\n    age:   25\nactive:   true\n")
        ),
        req("req_fmt_xml", "POST /format/xml", "POST", "/format/xml", "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("<root><child><name>Alice</name><age>30</age></child></root>")
        ),
        req("req_fmt_camel", "POST /format/camelCase", "POST", "/format/camelCase", "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("my_variable_name")
        ),
        req(
          "req_fmt_kebab",
          "POST /format/kebab-case",
          "POST",
          "/format/kebab-case",
          "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("myVariableName")
        ),
        req(
          "req_fmt_snake",
          "POST /format/snake_case",
          "POST",
          "/format/snake_case",
          "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("my-variable-name")
        ),
        req("req_fmt_upper", "POST /format/toUpper", "POST", "/format/toUpper", "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("hello world")
        ),
        req("req_fmt_lower", "POST /format/toLower", "POST", "/format/toLower", "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("HELLO WORLD")
        ),
        req(
          "req_fmt_collapse",
          "POST /format/collapse-lines",
          "POST",
          "/format/collapse-lines",
          "fld_format",
          headers: [content_type("text/plain")],
          body: text_body("line one\n\n\n\nline two\n\n\n\nline three")
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Codec
  # ---------------------------------------------------------------------------

  defp folder_codec do
    [folder("fld_codec", "Codec")] ++
      [
        req("req_enc_b64", "POST /encode/base64", "POST", "/encode/base64", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("Hello, Leywn!")
        ),
        req("req_dec_b64", "POST /decode/base64", "POST", "/decode/base64", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("SGVsbG8sIExleXduIQ==")
        ),
        req("req_enc_hex", "POST /encode/hex", "POST", "/encode/hex", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("Hello, Leywn!")
        ),
        req("req_dec_hex", "POST /decode/hex", "POST", "/decode/hex", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("48656c6c6f2c204c6579776e21")
        ),
        req("req_enc_url", "POST /encode/url", "POST", "/encode/url", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("hello world & foo=bar")
        ),
        req("req_dec_url", "POST /decode/url", "POST", "/decode/url", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("hello%20world%20%26%20foo%3Dbar")
        ),
        req("req_enc_rot13", "POST /encode/rot13", "POST", "/encode/rot13", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("Hello, Leywn!")
        ),
        req("req_dec_rot13", "POST /decode/rot13", "POST", "/decode/rot13", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body("Uryyb, Yrjla!")
        ),
        req("req_dec_jwt", "POST /decode/jwt", "POST", "/decode/jwt", "fld_codec",
          headers: [content_type("text/plain")],
          body: text_body(@jwt_example)
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Hash
  # ---------------------------------------------------------------------------

  defp folder_hash do
    [folder("fld_hash", "Hash")] ++
      [
        req("req_hash_sha256", "POST /hash/sha256", "POST", "/hash/sha256", "fld_hash",
          headers: [content_type("text/plain")],
          body: text_body("Hello, Leywn!")
        ),
        req("req_hash_md5", "POST /hash/md5", "POST", "/hash/md5", "fld_hash",
          headers: [content_type("text/plain")],
          body: text_body("Hello, Leywn!")
        )
      ]
  end

  # ---------------------------------------------------------------------------
  # Builders
  # ---------------------------------------------------------------------------

  defp folder(id, name, description \\ "") do
    %{
      "_id" => id,
      "_type" => "request_group",
      "parentId" => "wrk_leywn",
      "name" => name,
      "description" => description
    }
  end

  defp req(id, name, method, path, parent_id, opts \\ []) do
    %{
      "_id" => id,
      "_type" => "request",
      "parentId" => parent_id,
      "name" => name,
      "method" => method,
      "url" => "{{ base_url }}#{path}",
      "description" => Keyword.get(opts, :description, ""),
      "headers" => Keyword.get(opts, :headers, []),
      "body" => Keyword.get(opts, :body, %{}),
      "authentication" => Keyword.get(opts, :auth, %{})
    }
  end

  # ---------------------------------------------------------------------------
  # Header / body / auth helpers
  # ---------------------------------------------------------------------------

  defp header(name, value), do: %{"name" => name, "value" => value}
  defp content_type(ct), do: header("Content-Type", ct)
  defp bearer(token), do: header("Authorization", "Bearer #{token}")

  defp basic_auth(username, password) do
    %{"type" => "basic", "username" => username, "password" => password}
  end

  defp text_body(text), do: %{"mimeType" => "text/plain", "text" => text}

  defp json_body(json_str),
    do: %{"mimeType" => "application/json", "text" => json_str}

  defp form_body(pairs),
    do: %{
      "mimeType" => "application/x-www-form-urlencoded",
      "params" => Enum.map(pairs, fn {k, v} -> %{"name" => k, "value" => v} end)
    }
end
