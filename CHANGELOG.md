# Changelog

All notable changes to Leywn are documented in this file.

## [0.5.2.1] - 2026-04-08

### Fixed
- **mTLS handshake** — replaced `partial_chain` (client-side only in OTP SSL, silently ignored on server) with `verify_fun` so that the self-signed demo CA is accepted when verifying client certificates on OTP 26+

### Changed
- Version bumped to `0.5.2.1` in `mix.exs`

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
