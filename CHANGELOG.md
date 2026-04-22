# Changelog

All notable changes to Leywn are documented in this file.

## [1.0.0-beta4] - 2026-04-22

  ### Security
  - **H1 — PNG pixel budget** — `GET /image/color/{rgb}/{w}/{h}` now rejects requests whose total pixel count exceeds 1 048 576 (1 MP); previously `4096×4096` allocated ~50 MB per request
  - **H2 — YAML parsing DoS** — `POST /format/yaml` now rejects bodies larger than 16 384 bytes before parsing, and wraps `YamlElixir.read_from_string/1` in a `try/catch` to survive pathological anchor-expansion inputs
  - **M1 — CORS header injection** — `LEYWN_CORS_ORIGIN` value is stripped of CR/LF before being placed into the `Access-Control-Allow-Origin` response header
  - **M2 — Host header injection** — the `Host` request header is now validated against `[a-zA-Z0-9._-]+(:\d+)?` before being reflected into OpenAPI `servers` or the Insomnia button URL; invalid values fall back to `localhost`
  - **M3 — Internal error leakage** — `inspect(reason)` removed from the body-read error path in `body.ex` and the format/codec handler in `router.ex`; both now return generic opaque error strings
  - **M4 — Connection exhaustion** — Cowboy `max_connections` set to 1 000 on both HTTP and HTTPS listeners, capping the total number of concurrent connections
  - **Low — mTLS PEM header size** — certificate header value capped at 16 384 bytes before any parsing; rejects oversized values with a 401

  ### Added
  - **`ANY /chaos-engineering`** — echo response with configurable random fault injection: error codes (random 4xx/5xx), mangled JSON (truncated mid-stream), and latency. Defaults: `error_percentage=10`, `mangled_percentage=10`, `latency_percentage=20`, `maximum_latency=2000`. Parameters accepted as path segments (`/chaos-engineering/{ep}/{mp}/{lp}/{ml}`) or as `X-Chaos-*` request headers. Response always includes a `_chaos` meta field with applied parameters and actual latency.
  - **LICENSE** — BSD 2-Clause license added at repository root
  - **GitHub Actions CI** — `.github/workflows/ci.yml` runs `mix format --check-formatted` and the full test suite on every push/PR via the Docker `test` stage
  - **`.dockerignore`** — `_build/`, `deps/`, `.git/` excluded from the Docker build context for faster builds
  - **CI badge** — `README.md` now shows a live CI status badge and a Docker Hub pulls badge

  ### Fixed
  - **`/delay/{ms}` no longer silently clamps** — requests with `ms > 30000` now return `400` with `{error: "delay_too_large", maximum_ms: 30000, provided_ms: n}`
  - **`/stream/{n}` no longer silently clamps** — requests with `n > 100` now return `400` with `{error: "count_too_large", maximum: 100, provided: n}`
  - **`/random/lorem-ipsum/{n}` no longer silently clamps** — requests with `n > 32` now return `400` with `{error: "count_too_large", maximum: 32, provided: n}` instead of silently returning 32 paragraphs
  - **Swagger UI "Try it out" CORS / mixed-content error** — `/openapi.json` now always lists the request's own origin (`scheme://host`) as the first server entry, so Swagger UI calls back to the same origin the page was loaded from; configured `LEYWN_EXTERNAL_*` URLs appear as additional entries rather than replacing the first
  - **Insomnia "Run" button fetching wrong URL** — `collection_url` and `InsomniaCollection.build/1` now prefer `LEYWN_EXTERNAL_HTTPS_URL` over `LEYWN_EXTERNAL_HTTP_URL`, falling back to the request-derived URL; prevents Insomnia fetch failures when only the HTTP external URL was configured on an HTTPS-only server
  - **Custom API key headers blocked by CORS preflight** — `Access-Control-Allow-Headers` changed from an explicit allowlist (`Content-Type, Accept, Authorization`) to `*`; previously any request carrying a non-listed header (e.g. `apikey`, `X-Token`) was silently rejected by the browser before reaching the server

  ### Removed
  - **Mix scaffold files** — `lib/leywn.ex` (`hello/0`) and the corresponding scaffold test removed

  ### Changed
  - **Docker image references** — `README.md` now links to `svenwal/leywn` on Docker Hub
  - Version bumped to `1.0.0-beta4` in `mix.exs` and `openapi.json`

---

## [1.0.0-beta3] - 2026-04-22

  ### Changed
  - **Docker runtime image switched from Debian to Alpine** — base image changed from `debian:bullseye-slim` to `alpine:3.21.3`; builder and test stages now use `hexpm/elixir:...-alpine-3.21.3`; total image size reduced from 93 MB to 38 MB
  - **OTP application trimming** — `mix release` now only bundles OTP apps required by the transitive dependency graph, dropping unused apps automatically
  - **BEAM debug chunks stripped** — `strip_beams: true` in release config removes `Dbgi` and `Docs` chunks from all `.beam` files
  - **OpenShift-compatible security posture** — image runs as non-root (`USER 1001`); all release files owned `1001:0` via `COPY --chown`; permissions set to `g=u` in the builder stage so OpenShift's arbitrary-UID injection (GID 0) works without modification; `HOME=/tmp` set for Erlang runtime compatibility
  - **Fixed `Mix.Project` unavailable in release** — `/health` version field now uses `Application.spec(:leywn, :vsn)` instead of `Mix.Project.config()[:version]`, which is not available outside of a Mix environment
  - Version bumped to `1.0.0-beta3` in `mix.exs` and `openapi.json`

---

## [1.0.0-beta2] - 2026-04-22

  ### Added
  - **`LEYWN_EXTERNAL_HTTP_URL` / `LEYWN_EXTERNAL_HTTPS_URL`** — public base URLs for reverse-proxy deployments; when set, the Insomnia collection `base_url` environment variable and the OpenAPI `servers` array use these values instead of `localhost`
  - **"Run in Insomnia" button** — homepage header now shows an Insomnia run button (upper right) that links directly to `/request-collection`; the button URL automatically uses `LEYWN_EXTERNAL_HTTP_URL` when configured

  ### Changed
  - Homepage description text rewritten to better explain the project's purpose and key features
  - Docker image size reduced from ~229 MB to ~93 MB by moving WebP generation from runtime to build time (eliminates `libllvm11`, Mesa GL, and `freeglut3` from the runtime image)
  - Version bumped to `1.0.0-beta2` in `mix.exs` and `openapi.json`

---

## [1.0.0-beta1] - 2026-04-21

  ### Added
  - **`GET /request-collection`** — serves a dynamically generated Insomnia v4 export collection covering every endpoint, with example request bodies, auth headers, and a `base_url` environment variable set to the running server's HTTP port. Offered as a `Content-Disposition: attachment` download.
  - **CORS** — `Access-Control-Allow-*` headers added to every response via a new `Leywn.CORS` plug; `OPTIONS` preflight requests return `204 No Content`. Allowed origin configurable via `LEYWN_CORS_ORIGIN` (default: `*`)
  - **`GET /health`** — health check endpoint returning `status`, `version`, and `uptime_seconds`; suitable for use as a Kubernetes liveness/readiness probe
  - **`ANY /delay/{ms}`** — delays the response by the requested milliseconds (clamped to 30 000 ms); useful for testing timeouts and retry logic
  - **`GET /stream/{n}`** — chunked `application/x-ndjson` response streaming `n` JSON lines (max 100); each line is flushed individually
  - **`GET /random/name`** — random first name drawn from `priv/names.txt`; path overridable via `LEYWN_NAMES_FILE`
  - **`GET /random/email`** — random email address built from names and domains files; domain path overridable via `LEYWN_EMAIL_DOMAINS_FILE`
  - **`GET /random/color`** — random RGB colour returned as `{hex, r, g, b}`
  - **`POST /encode/hex` / `/decode/hex`** — hex encode/decode the request body
  - **`POST /hash/sha256` / `/hash/md5`** — hash the request body; returns `{hash, algorithm, input_bytes}`
  - `priv/names.txt` and `priv/email_domains.txt` — data files for the name and email generators; can be replaced/mounted to customise the output
  - Test stage added to the Dockerfile (`--target test`)
  - ExUnit test suites for all new endpoints: `random_ext_test.exs`, `hash_test.exs`, `delay_stream_health_test.exs`; hex codec tests added to `codec_test.exs`
  - `README.md` created with full endpoint reference and configuration table
  - `/random` bundle now includes `name`, `email`, and `color` fields

  ### Changed
  - **`/format/yaml`** — now accepts YAML input and re-formats it with 2-space indentation (previously converted JSON → YAML); uses `yaml_elixir` + `yamerl` (pure Erlang, no C NIFs)
  - **`/format/xml`** — now accepts XML input and re-formats it with 2-space indentation and an XML declaration header (previously converted JSON → XML); uses OTP's built-in `:xmerl` parser
  - Version bumped to `1.0.0` in `mix.exs` and `openapi.json`
  - OpenAPI spec updated: new `Hash` tag; new schemas `HealthResponse`, `DelayResponse`, `ColorResponse`, `HashResponse`; `RandomAll` schema extended; `badrequest` reusable response added

---

## [0.6.0] - 2026-04-14

### Added
- **`LEYWN_ONLY_JSON`** — set to `true` to disable XML content negotiation and always return JSON
- **Format endpoints** (`POST /format/*`) — prettify / transform a POST body:
  - `/format/json` — pretty-print JSON
  - `/format/yaml` — convert JSON to YAML
  - `/format/xml` — convert JSON to XML
  - `/format/camelCase` — recursively convert all JSON keys to camelCase
  - `/format/kebab-case` — recursively convert all JSON keys to kebab-case
  - `/format/snake-case` — recursively convert all JSON keys to snake_case
  - `/format/toUpper` — uppercase the body text
  - `/format/toLower` — lowercase the body text
  - `/format/collapse-lines` — collapse multiple consecutive blank lines into one
- **Codec endpoints** (`POST /encode/*` and `POST /decode/*`) — encode/decode a POST body:
  - `/encode/base64`, `/decode/base64`
  - `/encode/url`, `/decode/url`
  - `/encode/rot13`, `/decode/rot13`
  - `/decode/jwt` — decode JWT header and payload (no signature verification)
- **Extended image endpoints**:
  - `jpg` accepted as alias for `jpeg`
  - `/image/svg` — dynamic SVG with Leywn branding
  - `/image/webp` — Leywn logo re-encoded as WebP (converted from PNG at startup using `cwebp`)
  - `/image/color/{rgb}` — 64×64 PNG solid-colour image (3-char, 6-char, or 8-char hex)
  - `/image/color/{rgb}/{width}/{height}` — solid-colour PNG at custom size (max 4096×4096)
- **ExUnit test suites** for all new endpoints: `format_test.exs`, `codec_test.exs`, `image_test.exs`

### Changed
- Home page header redesigned: `#1a1a2e` background with logo + "Last Echo You Will Need" text
- Home page description updated to highlight lightweight, fast, customisable nature
- Dockerfile runtime image now includes `webp` package for WebP generation
- Version bumped to `0.6.0` in `mix.exs`

---

## [0.5.4] - 2026-04-10

### Fixed
- **mTLS security** — `/auth/mtls` previously accepted any client certificate; the server-side `verify_fun` now rejects certificates not issued by the Leywn CA (or the CA behind `LEYWN_MTLS_CERT`), so only the correct client certificate is accepted

### Added
- **mTLS ExUnit tests** — `test/mtls_test.exs` covers three scenarios: no certificate (expect HTTP 401), wrong self-signed certificate (expect TLS handshake rejection), and the correct certificate (expect HTTP 200 with `authenticated: true`)

### Changed

- Version bumped to `0.5.4` in `mix.exs`
- `Server` response header changed from `Cowboy` to `leywn`

---

## [0.5.3] - 2026-04-08

### Fixed
- **mTLS handshake** — replaced `partial_chain` (client-side only in OTP SSL, silently ignored on server) with `verify_fun` so that the self-signed demo CA is accepted when verifying client certificates on OTP 26+

### Changed
- Version bumped to `0.5.3` in `mix.exs`

---

## [0.5.2] - 2026-04-08

### Fixed
- **mTLS handshake** — added `partial_chain` callback so OTP 26+ accepts the self-signed demo CA when verifying client certificates (previously failed with `:selfsigned_peer`)

### Changed
- Version bumped to `0.5.2` in `mix.exs`

---

## [0.5.1] - 2026-04-08

### Added
- **`LEYWN_MTLS_CERT` / `LEYWN_MTLS_KEY`** — supply a custom PEM-encoded client certificate and private key for mTLS; when set, the provided cert+key are served at `/auth/mtls/get-client-cert` and the server automatically trusts the issuing CA so the TLS handshake succeeds
- **Multi-stage Docker build** — the runtime image now uses a minimal `debian:bullseye-slim` base (~97 MB) with only the compiled OTP release copied in; build toolchain, source code, and Mix are no longer present at runtime

### Changed
- Version bumped to `0.5.1` in `mix.exs`

---

## [0.5.0] - 2026-04-08

### Added
- **`LEYWN_TLS_SERVER_KEY` / `LEYWN_TLS_SERVER_CRT`** — supply a custom PEM-encoded private key and certificate for the HTTPS listener instead of the auto-generated one; expired certificates log a warning and are still accepted, syntactically invalid certificates stop the server with an error
- **Request logging** — every request is now logged to stdout as a single line: `timestamp METHOD /path remote=IP status=CODE duration=Xms`
- **Dynamic OpenAPI `servers`** — the `/openapi.json` response now injects a `servers` array reflecting the actual `LEYWN_PORT` and `LEYWN_TLS_PORT` values instead of hardcoded defaults
- Slimmed down the Docker image size by removing unneeded source files

### Changed
- Version bumped to `0.5.0` in `mix.exs`

---

## [0.4.0] - 2026-04-01

### Added
- **Info endpoints** — `/ip`, `/ip/v4`, `/ip/v6` return the caller's IP address(es)
  - `LEYWN_TRUST_FORWARD=true` — use the first value from `X-Forwarded-For` instead of the socket address
- **Date/time endpoints** — `/date`, `/date/{timezone}`, `/time`, `/time/{timezone}`
  - Full IANA timezone support via the `tzdata` dependency
  - Unknown timezones return HTTP 404
- **JWT exchange** — `ANY /auth/jwt/exchange` validates an incoming Bearer JWT and issues a new HS256-signed token with `iss: leywn`, `iat`, and `jti` added
- **`/docs`** — alias for the home page / Swagger UI
- **`LEYWN_ECHO_ON_HOME=true`** — serve echo output on `/` instead of the HTML home page
- OpenAPI spec updated: all endpoints now carry tags (Echo, Auth, Random, Info, Utility); added `securitySchemes`; new schemas for IP, date, time, and JWT exchange responses

### Changed
- Version bumped to `0.4.0` in `mix.exs`

---

## [0.3.0]

### Added
- **Auth endpoints** — `/auth/basic-auth`, `/auth/basic-auth/{user}/{pass}`, `/auth/api-key`, `/auth/api-key/{header}/{value}`, `/auth/jwt`, `/auth/mtls`, `/auth/mtls/get-client-cert`
  - mTLS listener on a second port (default 4443); CA, server cert, and client cert/key generated in memory at startup
  - `LEYWN_MTLS_CERT` / `LEYWN_MTLS_KEY` — use externally provided PEM certificates instead of generated ones
  - `LEYWN_MTLS_IN_HEADER` — read the client certificate from a named request header (proxy/load-balancer mode)
- **Home page** (`/`) — HTML page with project overview and embedded Swagger UI served from `/openapi.json`
- **OpenAPI spec** — `/openapi.json` with full endpoint descriptions and example requests/responses
- **XML support** — all structured endpoints honour `Accept: application/xml`

---

## [0.2.0]

### Added
- **UUID/GUID endpoints** — `GET /uuid` (UUID v4), `GET /guuid` (UUID v4 wrapped in curly braces)
- **Random endpoints** — `/random`, `/random/int`, `/random/int/{lower}/{upper}`, `/random/uint`, `/random/lorem-ipsum`, `/random/lorem-ipsum/{count}` (max 32 paragraphs)
- **Image endpoint** — `GET /image/{type}` serves `png`, `jpeg`, or `gif` from the `images/` folder
- **`LEYWN_ECHO_MAX_BODY_BYTES`** — configurable body size limit for echo endpoints (default 65536)

---

## [0.1.0]

### Added
- **Echo endpoints** — `ANY /echo` and `ANY /echo/{path}` return method, scheme, host, port, path, query parameters, headers, remote IP, body, and timestamp
- **`/anything`** — alias for `/echo` (also matches sub-paths)
- **Status endpoint** — `ANY /status/{code}` responds with any HTTP status code in 100–599
- Runtime configuration via `LEYWN_PORT` (default 4000) and `LEYWN_TLS_PORT` (default 4443)
- Dockerfile for containerised deployment
