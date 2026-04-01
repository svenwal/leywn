# Leywn — Last Echo You Will Need

Leywn is an all-in-one demo/test backend for APIs and HTTP services. It gives you a single deployable service that echoes requests, enforces every common authentication scheme, returns arbitrary HTTP status codes, generates random data, and serves a live Swagger UI — so you can test clients, proxies, load balancers, and API gateways without standing up any real backend.

---

## Table of contents

- [Quick start](#quick-start)
- [Installation](#installation)
  - [Docker (recommended)](#docker-recommended)
  - [Docker Compose](#docker-compose)
  - [Local (Elixir / Mix)](#local-elixir--mix)
- [Configuration](#configuration)
- [Endpoints](#endpoints)
  - [/ — Swagger UI](#----swagger-ui)
  - [/echo — Request mirror](#echo--request-mirror)
  - [/anything — Echo alias](#anything--echo-alias)
  - [/status/{code} — HTTP status codes](#statuscode--http-status-codes)
  - [/auth/basic-auth — Basic authentication](#authbasic-auth--basic-authentication)
  - [/auth/api-key — API key authentication](#authapikey--api-key-authentication)
  - [/auth/jwt — JWT Bearer authentication](#authjwt--jwt-bearer-authentication)
  - [/auth/jwt/exchange — JWT exchange](#authjwtexchange--jwt-exchange)
  - [/auth/mtls — mTLS client certificate authentication](#authmtls--mtls-client-certificate-authentication)
  - [/uuid — UUID v4](#uuid--uuid-v4)
  - [/guuid — GUID](#guuid--guid)
  - [/image/{type} — Demo images](#imagetype--demo-images)
  - [/random — Random data](#random--random-data)
  - [/ip — Caller IP address](#ip--caller-ip-address)
  - [/date — Current date](#date--current-date)
  - [/time — Current time](#time--current-time)
- [Content negotiation](#content-negotiation)
- [Use cases](#use-cases)
- [Code structure](#code-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Quick start

```bash
docker run -p 4000:4000 -p 4443:4443 ghcr.io/svenwal/leywn:latest
```

Open <http://localhost:4000> in your browser for the Swagger UI.

---

## Installation

### Docker (recommended)

**Pull and run the latest image:**

```bash
docker run -p 4000:4000 -p 4443:4443 ghcr.io/svenwal/leywn:latest
```

**Build from source:**

```bash
git clone https://github.com/svenwal/leywn.git
cd leywn/Leywn/leywn
docker build -t leywn .
docker run -p 4000:4000 -p 4443:4443 leywn
```

Port `4000` serves plain HTTP. Port `4443` serves HTTPS with a self-signed server certificate and mTLS support (client certificate optional except on `/auth/mtls`).

### Docker Compose

Create a `docker-compose.yml`:

```yaml
services:
  leywn:
    image: ghcr.io/svenwal/leywn:latest
    ports:
      - "4000:4000"
      - "4443:4443"
    environment:
      LEYWN_PORT: 4000
      LEYWN_TLS_PORT: 4443
      LEYWN_ECHO_MAX_BODY_BYTES: 65536
```

Then:

```bash
docker compose up
```

### Local (Elixir / Mix)

Prerequisites: [Elixir 1.18+](https://elixir-lang.org/install.html) and Erlang/OTP 27+.

```bash
git clone https://github.com/svenwal/leywn.git
cd leywn/Leywn/leywn
mix deps.get
mix run --no-halt
```

The server starts on `http://localhost:4000` and `https://localhost:4443`.

---

## Configuration

All settings are controlled through environment variables.

| Variable | Default | Description |
|---|---|---|
| `LEYWN_PORT` | `4000` | HTTP listen port |
| `LEYWN_TLS_PORT` | `4443` | HTTPS / mTLS listen port |
| `LEYWN_ECHO_MAX_BODY_BYTES` | `65536` | Maximum request body size echoed back (64 KB) |
| `LEYWN_ECHO_ON_HOME` | _(unset)_ | When set to `true`, serve echo output on `/` instead of the HTML home page |
| `LEYWN_MTLS_IN_HEADER` | _(unset)_ | When set to a header name, read the client certificate PEM from that header instead of the TLS handshake (see [proxy mode](#proxy--load-balancer-mode)) |
| `LEYWN_MTLS_CERT` | _(unset)_ | PEM-encoded server certificate to use instead of the generated one |
| `LEYWN_MTLS_KEY` | _(unset)_ | PEM-encoded private key for `LEYWN_MTLS_CERT` |
| `LEYWN_TRUST_FORWARD` | _(unset)_ | When set to `true`, derive the caller IP from the `X-Forwarded-For` header instead of the socket address |

Example with custom ports:

```bash
docker run -e LEYWN_PORT=8080 -e LEYWN_TLS_PORT=8443 -p 8080:8080 -p 8443:8443 leywn
```

---

## Endpoints

All endpoints support JSON (default) and XML responses via content negotiation — see [Content negotiation](#content-negotiation).

### / — Swagger UI

```
GET /
```

Serves an HTML page with a [Swagger UI](https://swagger.io/tools/swagger-ui/) loaded from `/openapi.json`. Use it to explore and try every endpoint interactively.

```bash
open http://localhost:4000
```

---

### /echo — Request mirror

```
ANY /echo
ANY /echo/{*path}
```

Returns every detail of the incoming request: method, scheme, host, port, path, query parameters, headers, remote IP, and body (if text/UTF-8 and within the size limit).

```bash
# Basic GET
curl http://localhost:4000/echo

# POST with body and query params
curl -X POST "http://localhost:4000/echo/foo/bar?hello=world" \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'
```

**Example response:**

```json
{
  "method": "POST",
  "scheme": "http",
  "host": "localhost",
  "port": 4000,
  "path": "/echo/foo/bar",
  "path_info": ["foo", "bar"],
  "query_string": "hello=world",
  "query_params": { "hello": "world" },
  "headers": {
    "content-type": ["application/json"],
    "host": ["localhost:4000"]
  },
  "remote_ip": "127.0.0.1",
  "body": {
    "present": true,
    "bytes": 18,
    "truncated": false,
    "utf8": true,
    "included": true,
    "body": "{\"message\": \"test\"}"
  },
  "timestamp_unix_ms": 1700000000000
}
```

Bodies larger than `ECHO_MAX_BODY_BYTES` are acknowledged but not included (`truncated: true`). Binary bodies are detected and excluded (`utf8: false, included: false`).

---

### /anything — Echo alias

```
ANY /anything
ANY /anything/{*path}
```

Identical to `/echo`. Provided as a convenience alias familiar to users of similar tools.

```bash
curl -X DELETE http://localhost:4000/anything/some/path
```

---

### /status/{code} — HTTP status codes

```
ANY /status/{code}
```

Responds with the exact HTTP status code you specify (100–599).

- **1xx and 204/304** — empty body
- **All others** — JSON body `{"status": <code>}`

```bash
# Trigger a 418 I'm a teapot
curl -i http://localhost:4000/status/418

# Test how your client handles 503
curl -i http://localhost:4000/status/503

# Test redirects
curl -iL http://localhost:4000/status/301
```

---

### /auth/basic-auth — Basic authentication

**Default credentials** (`basic` / `password`):

```
ANY /auth/basic-auth
```

```bash
# Correct credentials
curl -u basic:password http://localhost:4000/auth/basic-auth

# Wrong credentials → 401
curl -u wrong:credentials http://localhost:4000/auth/basic-auth

# No credentials → 401 with WWW-Authenticate header
curl -i http://localhost:4000/auth/basic-auth
```

**Custom credentials** in the URL path:

```
ANY /auth/basic-auth/{username}/{password}
```

```bash
curl -u alice:secret http://localhost:4000/auth/basic-auth/alice/secret
```

**Success response** includes `authenticated: true`, `auth_type: "basic-auth"`, `username`, plus the full echo payload.

---

### /auth/api-key — API key authentication

**Default** (header `apikey: my-key`):

```
ANY /auth/api-key
```

```bash
# Correct key
curl -H "apikey: my-key" http://localhost:4000/auth/api-key

# Wrong key → 401
curl -H "apikey: wrong" http://localhost:4000/auth/api-key
```

**Custom header name and value:**

```
ANY /auth/api-key/{header_name}/{key_value}
```

```bash
curl -H "X-Api-Token: supersecret" \
  http://localhost:4000/auth/api-key/X-Api-Token/supersecret
```

---

### /auth/jwt — JWT Bearer authentication

```
ANY /auth/jwt
```

Validates the structure of a JWT in the `Authorization: Bearer <token>` header. The signature is **not** verified — this endpoint validates format and decodes header/claims, making it useful for testing token generation and parsing.

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IkFsaWNlIn0.signature"

curl -H "Authorization: Bearer $TOKEN" http://localhost:4000/auth/jwt
```

**Success response** includes the decoded `jwt_header` and `claims` maps alongside the echo payload.

```json
{
  "authenticated": true,
  "auth_type": "jwt",
  "jwt_header": { "alg": "HS256", "typ": "JWT" },
  "claims": { "sub": "user123", "name": "Alice" },
  "method": "GET",
  ...
}
```

---

### /auth/jwt/exchange — JWT exchange

```
ANY /auth/jwt/exchange
```

Validates the incoming `Authorization: Bearer <token>` JWT (structure only, signature not verified), then issues a new HS256-signed token with the original claims merged with `iss: "leywn"`, `iat` (issued-at), and a fresh `jti` (JWT ID).

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMTIzIn0.signature"
curl -H "Authorization: Bearer $TOKEN" http://localhost:4000/auth/jwt/exchange
```

**Success response** includes `exchanged_token` (the new signed JWT) and the updated `claims` alongside the echo payload:

```json
{
  "authenticated": true,
  "auth_type": "jwt",
  "exchanged_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "claims": { "sub": "user123", "iss": "leywn", "iat": 1700000000, "jti": "..." },
  "method": "POST",
  ...
}
```

---

### /auth/mtls — mTLS client certificate authentication

```
ANY /auth/mtls             (HTTPS port 4443 only, or header mode on any port)
GET /auth/mtls/get-client-cert
```

A fresh CA, server certificate, and client certificate are generated on every startup and kept in memory. The `/auth/mtls` endpoint validates that the caller presents a certificate signed by that CA.

#### Direct TLS handshake

Use the HTTPS port with the generated client certificate:

```bash
# Step 1: download the client certificate and key
curl -k https://localhost:4443/auth/mtls/get-client-cert \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
open('client.pem','w').write(d['cert_pem'])
open('client.key','w').write(d['key_pem'])
print('saved client.pem and client.key')
"

# Step 2: call /auth/mtls with the client cert
curl -k --cert client.pem --key client.key https://localhost:4443/auth/mtls
```

**Success response** includes `client_dn` and `client_ca` extracted from the certificate:

```json
{
  "authenticated": true,
  "auth_type": "mtls",
  "client_dn": "CN=Leywn Demo Client",
  "client_ca": "CN=Leywn Demo CA",
  ...
}
```

#### Proxy / load-balancer mode

When a TLS-terminating proxy (e.g. Nginx, AWS ALB, Envoy) handles the TLS handshake and forwards the client certificate in a header, set `LEYWN_MTLS_IN_HEADER` to the header name:

```bash
docker run -e LEYWN_MTLS_IN_HEADER=X-Client-Cert -p 4000:4000 leywn
```

Leywn will then read the PEM certificate from that header (URL-encoded is accepted) instead of the TLS peer data:

```bash
# URL-encode the PEM and pass it in the configured header
CERT=$(python3 -c "import urllib.parse; print(urllib.parse.quote(open('client.pem').read()))")
curl http://localhost:4000/auth/mtls -H "X-Client-Cert: $CERT"
```

---

### /uuid — UUID v4

```
GET /uuid
```

Returns a randomly generated [UUID v4](https://datatracker.ietf.org/doc/html/rfc4122).

```bash
curl http://localhost:4000/uuid
# {"uuid":"6986f945-a01e-4ffd-aff8-a15648be7946"}
```

---

### /guuid — GUID

```
GET /guuid
```

Returns a UUID v4 wrapped in curly braces, in the Windows GUID format.

```bash
curl http://localhost:4000/guuid
# {"guuid":"{d3afb989-99bf-49b2-9cd6-820c039a1e6f}"}
```

---

### /image/{type} — Demo images

```
GET /image/png
GET /image/jpeg
GET /image/gif
```

Serves the Leywn demo image in the requested format. Useful for testing image rendering, CDN caching headers, or client-side image loading.

```bash
curl -o logo.png http://localhost:4000/image/png
open http://localhost:4000/image/gif
```

---

### /random — Random data

#### All random values at once

```
GET /random
```

Returns one sample of every random type in a single response.

```bash
curl http://localhost:4000/random
```

#### Signed integer

```
GET /random/int                     # range: -32000 to 32000
GET /random/int/{lower}/{upper}     # custom range (inclusive)
```

```bash
curl http://localhost:4000/random/int
# {"value": -14203}

curl http://localhost:4000/random/int/1/6
# {"value": 4}  (simulates a dice roll)

curl http://localhost:4000/random/int/-1000000/1000000
```

#### Unsigned integer

```
GET /random/uint    # range: 0 to 65535
```

```bash
curl http://localhost:4000/random/uint
# {"value": 42817}
```

#### Lorem Ipsum

```
GET /random/lorem-ipsum             # one paragraph
GET /random/lorem-ipsum/{n}         # n paragraphs, max 32
```

The first paragraph always opens with the classic sentence. Subsequent paragraphs are generated from a word pool, so each response is unique.

```bash
curl http://localhost:4000/random/lorem-ipsum
curl http://localhost:4000/random/lorem-ipsum/5
```

---

### /ip — Caller IP address

```
GET /ip         # both IPv4 and IPv6
GET /ip/v4      # IPv4 only
GET /ip/v6      # IPv6 only
```

Returns the caller's IP address(es). When `LEYWN_TRUST_FORWARD=true` is set, the first value from the `X-Forwarded-For` header is used instead of the socket address (useful behind a proxy or load balancer).

```bash
curl http://localhost:4000/ip
# {"ipv4":"127.0.0.1","ipv6":null}

curl http://localhost:4000/ip/v4
# {"ipv4":"127.0.0.1"}

curl http://localhost:4000/ip/v6
# {"ipv6":null}
```

---

### /date — Current date

```
GET /date                   # UTC
GET /date/{timezone}        # any IANA timezone, e.g. America/New_York
```

Returns the current date in ISO 8601 format. Unknown timezones return HTTP 404.

```bash
curl http://localhost:4000/date
# {"date":"2026-04-01","timezone":"UTC"}

curl http://localhost:4000/date/Europe/Berlin
# {"date":"2026-04-01","timezone":"Europe/Berlin"}

# Unknown timezone → 404
curl -i http://localhost:4000/date/Invalid/Zone
```

---

### /time — Current time

```
GET /time                   # UTC
GET /time/{timezone}        # any IANA timezone, e.g. Asia/Tokyo
```

Returns the current time as a full ISO 8601 datetime string. Unknown timezones return HTTP 404.

```bash
curl http://localhost:4000/time
# {"time":"2026-04-01T12:34:56.789Z","timezone":"UTC"}

curl http://localhost:4000/time/Asia/Tokyo
# {"time":"2026-04-01T21:34:56.789+09:00","timezone":"Asia/Tokyo"}
```

---

## Content negotiation

Every endpoint defaults to JSON. Pass `Accept: application/xml` to receive an XML response instead.

```bash
# JSON (default)
curl http://localhost:4000/echo

# XML
curl -H "Accept: application/xml" http://localhost:4000/echo

# XML for auth
curl -u basic:password \
  -H "Accept: application/xml" \
  http://localhost:4000/auth/basic-auth
```

---

## Use cases

### Testing HTTP client behaviour

Point any HTTP client, SDK, or library at `/echo` to inspect exactly what it sends — headers it adds automatically, how it encodes the body, whether it follows redirects, etc.

```bash
# See what headers your HTTP library adds
curl http://localhost:4000/echo

# Verify a POST body is encoded correctly
curl -X POST http://localhost:4000/echo \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "field1=value1&field2=value2"
```

### Testing retry and error-handling logic

Use `/status/{code}` to reliably trigger any HTTP status code and verify your client handles it correctly.

```bash
# Test 429 rate-limit handling
curl -i http://localhost:4000/status/429

# Test 503 retry logic
curl -i http://localhost:4000/status/503

# Test 401 token-refresh flow
curl -i http://localhost:4000/status/401
```

### Testing authentication middleware

Verify that your API gateway or middleware correctly extracts and validates credentials.

```bash
# Does your gateway forward the Authorization header?
curl -u basic:password http://localhost:4000/auth/basic-auth | jq .headers

# Does your proxy strip or rename auth headers?
curl -H "apikey: my-key" http://localhost:4000/auth/api-key | jq .headers
```

### Testing a TLS-terminating proxy

Run Leywn in header mode and configure your proxy to forward client certificates:

```bash
# Nginx example: proxy_set_header X-Client-Cert $ssl_client_escaped_cert;
docker run -e LEYWN_MTLS_IN_HEADER=X-Client-Cert -p 4000:4000 leywn
```

Leywn will validate the certificate and report `client_dn` / `client_ca` so you can confirm the proxy is forwarding the right certificate.

### Generating test data

Use the `/random` endpoints to fill forms, seed databases, or drive load tests with varied input.

```bash
# Generate 10 UUIDs
for i in $(seq 10); do curl -s http://localhost:4000/uuid | jq -r .uuid; done

# Random payload for a load test
curl -s http://localhost:4000/random/lorem-ipsum/2 | jq -r '.paragraphs[]'
```

### Testing XML consumers

Use `Accept: application/xml` to verify that your XML parser or XSLT stylesheet handles the response structure correctly.

```bash
curl -H "Accept: application/xml" http://localhost:4000/echo
```

---

## Code structure

```
lib/
├── leywn/
│   ├── application.ex   # OTP Application — starts HTTP + HTTPS listeners
│   ├── router.ex        # Plug.Router — all route definitions and home page HTML
│   ├── echo.ex          # Builds the echo response map from a Plug.Conn
│   ├── body.ex          # Reads and inspects the request body
│   ├── auth.ex          # All authentication handlers (basic, api-key, jwt, mtls)
│   ├── mtls.ex          # Generates CA / server / client certificates at startup
│   ├── random.ex        # UUID, integer, and Lorem Ipsum generators
│   ├── logos.ex         # Resolves image file paths
│   ├── info.ex          # IP address, date, and time helpers
│   └── respond.ex       # Content negotiation and JSON/XML serialisation
└── leywn.ex

config/
├── config.exs           # Compile-time defaults
└── runtime.exs          # Runtime configuration from environment variables

priv/
├── openapi.json         # OpenAPI 3.0 specification (served at /openapi.json)
└── images/
    ├── leywn.png
    ├── leywn.jpeg
    └── leywn.gif
```

**Key dependencies:**

| Package | Purpose |
|---|---|
| `plug_cowboy` | HTTP/HTTPS server |
| `jason` | JSON encoding/decoding |
| `xml_builder_ex` | XML serialisation |
| `tzdata` | IANA timezone database for `/date` and `/time` |

Certificate generation uses Erlang's built-in `:public_key` and `:crypto` modules — no external PKI dependencies.

---

## Contributing

Contributions are welcome. Please follow these guidelines:

1. **Fork and branch** — create a feature branch from `main`.
2. **All code in Elixir** — the project is intentionally pure Elixir/OTP for portability and minimal footprint.
3. **Build and test via Docker** — do not assume a local Elixir installation. Always verify with `docker build` and a `docker run` smoke test.
4. **New endpoints** — add the route to `router.ex`, implement logic in a dedicated module under `lib/leywn/`, and add the path to `priv/openapi.json` and the home page listing in `router.ex`.
5. **Content negotiation** — every endpoint that returns structured data must support both JSON and XML via `Leywn.Respond.send/4`.
6. **Keep it focused** — Leywn is a demo/test tool, not a framework. Avoid adding runtime dependencies unless strictly necessary.

**Reporting issues:** open an issue at <https://github.com/svenwal/leywn/issues>.

---

## License

MIT — see [LICENSE](LICENSE) for details.
