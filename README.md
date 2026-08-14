# Leywn — Last Echo You Will Need

[![CI](https://img.shields.io/github/actions/workflow/status/svenwal/leywn/ci.yml?label=CI)](https://github.com/svenwal/leywn/actions/workflows/ci.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/svenwal/leywn)](https://hub.docker.com/r/svenwal/leywn)
[![Live](https://img.shields.io/badge/live-leywn.org-blue)](https://leywn.org)

Leywn is an all-in-one demo/test backend for APIs and HTTP services. It gives you a single deployable service that echoes requests, enforces every common authentication scheme, returns arbitrary HTTP status codes, generates random data, serves mock REST APIs from plain JSON files, and hosts a live Swagger UI — so you can test clients, proxies, load balancers, and API gateways without standing up any real backend.

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
  - [/health — Health check](#health--health-check)
  - [/echo — Request mirror](#echo--request-mirror)
  - [/anything — Echo alias](#anything--echo-alias)
  - [/status/{code} — HTTP status codes](#statuscode--http-status-codes)
  - [/delay/{ms} — Response delay](#delayms--response-delay)
  - [/stream/{n} — Chunked streaming](#streamn--chunked-streaming)
  - [/chaos-engineering — Chaos engineering](#chaos-engineering--chaos-engineering)
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
  - [/format/* — Format and prettify](#format--format-and-prettify)
  - [/encode and /decode — Codec](#encode-and-decode--codec)
  - [/hash/* — Hashing](#hash--hashing)
  - [/mocks — Mock REST APIs](#mocks--mock-rest-apis)
- [Content negotiation](#content-negotiation)
- [Use cases](#use-cases)
- [Code structure](#code-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Quick start

```bash
docker run -p 4000:4000 -p 4443:4443 svenwal/leywn:latest
```

Open <http://localhost:4000> in your browser for the Swagger UI.

---

## Installation

### Docker (recommended)

**Pull and run the latest image:**

```bash
docker run -p 4000:4000 -p 4443:4443 svenwal/leywn:latest
```

**Build from source:**

```bash
git clone https://github.com/svenwal/leywn.git
cd leywn/Leywn/leywn
docker build -t leywn .
docker run -p 4000:4000 -p 4443:4443 leywn
```

Port `4000` serves plain HTTP. Port `4443` serves HTTPS with a self-signed server certificate and mTLS support (client certificate optional except on `/auth/mtls`).

The image uses a multi-stage build on an Alpine base: only the compiled OTP release is included in the final layer — no Mix, Hex, or source code at runtime (~38 MB). It runs as a non-root user (UID 1001, GID 0) and is compatible with OpenShift's arbitrary-UID injection.

### Docker Compose

Create a `docker-compose.yml`:

```yaml
services:
  leywn:
    image: svenwal/leywn:latest
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
| `LEYWN_TLS_SERVER_CRT` | _(unset)_ | PEM-encoded server certificate for the HTTPS listener; if set together with `LEYWN_TLS_SERVER_KEY`, used instead of the auto-generated one (expired → warning, invalid → error) |
| `LEYWN_TLS_SERVER_KEY` | _(unset)_ | PEM-encoded private key matching `LEYWN_TLS_SERVER_CRT` |
| `LEYWN_MTLS_CERT` | _(unset)_ | PEM-encoded client certificate (and optional CA chain) to use instead of the auto-generated one; served at `/auth/mtls/get-client-cert` and automatically trusted by the mTLS listener |
| `LEYWN_MTLS_KEY` | _(unset)_ | PEM-encoded private key matching `LEYWN_MTLS_CERT` |
| `LEYWN_TRUST_FORWARD` | _(unset)_ | When set to `true`, derive the caller IP from the `X-Forwarded-For` header instead of the socket address |
| `LEYWN_ONLY_JSON` | _(unset)_ | When set to `true`, disable XML content negotiation and always return JSON regardless of the `Accept` header |
| `LEYWN_CORS_ORIGIN` | `*` | Value of the `Access-Control-Allow-Origin` response header. When set to a specific origin, `Vary: Origin` is sent as well |
| `LEYWN_EXTERNAL_HTTP_URL` | _(unset)_ | Public HTTP base URL when running behind a reverse proxy; used in the OpenAPI `servers` list and the Insomnia collection |
| `LEYWN_EXTERNAL_HTTPS_URL` | _(unset)_ | Public HTTPS base URL when running behind a reverse proxy; preferred over the HTTP one |
| `LEYWN_NAMES_FILE` | `priv/names.txt` | Path to the name list backing `/random/name` and `/random/email` (one name per line, `#` comments allowed) |
| `LEYWN_EMAIL_DOMAINS_FILE` | `priv/email_domains.txt` | Path to the domain list backing `/random/email` (one domain per line) |

`LEYWN_TLS_SERVER_CRT` and `LEYWN_TLS_SERVER_KEY` must be set together — setting
only one aborts startup rather than silently falling back to a generated
certificate. The name and domain files are read once at first use and cached, so
replacing them requires a restart.

### Mock configuration

The mock endpoints are the only part of Leywn that accepts writes and keeps
state between requests, so they carry their own limits. The defaults are sized
for a demo backend: enough room to show a CRUD flow, not enough to store a
workload. See [/mocks](#mocks--mock-rest-apis) for what they do in practice.

| Variable | Default | Description |
|---|---|---|
| `LEYWN_MOCKS_DIR` | `priv/mocks` | Directory scanned at startup; each subfolder becomes one mock |
| `LEYWN_MOCK_READONLY` | _(unset)_ | When set to `true`, only `GET` is served and no state is ever created |
| `LEYWN_MOCK_ENTRY_TTL_SECONDS` | `300` | Seconds after which a written record — or a deletion — is forgotten |
| `LEYWN_MOCK_MAX_NEW_ENTRIES` | `100` | Maximum changes held per mock; further writes return `507` |
| `LEYWN_MOCK_MAX_OVERLAY_BYTES` | `1048576` | Total bytes of held changes across all mocks (1 MiB) |
| `LEYWN_MOCK_WRITE_RATE_LIMIT` | `60` | Mutating requests per minute, per client IP |
| `LEYWN_MOCK_WRITE_RATE_LIMIT_GLOBAL` | `600` | Mutating requests per minute across all clients |
| `LEYWN_MOCK_RATE_BUCKETS` | `10000` | Per-IP rate-limit rows tracked before falling back to the global budget alone |
| `LEYWN_MOCK_MAX_BODY_BYTES` | `16384` | Maximum body accepted by a mutating mock request (16 KB) |
| `LEYWN_MOCK_MAX_DEPTH` | `16` | Maximum nesting depth of a write body |
| `LEYWN_MOCK_MAX_KEYS` | `100` | Maximum keys in any single object of a write body |
| `LEYWN_MOCK_MAX_PAGE_SIZE` | `200` | Maximum records returned by one collection read |
| `LEYWN_MOCK_MAX_FILTERS` | `10` | Maximum query parameters honoured as field filters |
| `LEYWN_MOCK_MAX_FILE_BYTES` | `8388608` | Maximum size of a mock's JSON file (8 MiB); larger files are skipped with a warning |
| `LEYWN_MOCK_MAX_MOCKS` | `50` | Maximum number of mocks loaded from the directory |
| `LEYWN_MOCK_MAX_COLLECTIONS` | `100` | Maximum collections within a single mock |

Example with custom ports:

```bash
docker run -e LEYWN_PORT=8080 -e LEYWN_TLS_PORT=8443 -p 8080:8080 -p 8443:8443 leywn
```

---

## Endpoints

All endpoints support JSON (default) and XML responses via content negotiation — see [Content negotiation](#content-negotiation).

### / — Swagger UI

```
GET /            # home page with embedded Swagger UI
GET /docs        # alias for /
GET /openapi.json          # the OpenAPI 3.0 specification
GET /request-collection    # Insomnia v4 collection covering every endpoint
```

Serves an HTML page with a [Swagger UI](https://swagger.io/tools/swagger-ui/) loaded from `/openapi.json`. Use it to explore and try every endpoint interactively.

```bash
open http://localhost:4000
```

`/openapi.json` lists the origin the page was loaded from as its first server entry, so "Try it out" always calls back to the same host — plus any `LEYWN_EXTERNAL_*` URLs you configure. `/request-collection` is served as a download and its `base_url` environment variable is derived the same way.

Set `LEYWN_ECHO_ON_HOME=true` to serve echo output on `/` instead of the HTML page.

---

### /health — Health check

```
GET /health
```

Returns server status, version, and uptime. Suitable for use as a Kubernetes liveness/readiness probe.

```bash
curl http://localhost:4000/health
# {"status":"ok","version":"1.1.0-beta1","uptime_seconds":42}
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
    "content-type": "application/json",
    "host": "localhost:4000"
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

A header sent once is reported as a plain string; only a header that genuinely appears more than once becomes an array.

Bodies larger than `LEYWN_ECHO_MAX_BODY_BYTES` are acknowledged but not included (`truncated: true`). Binary bodies are detected and excluded (`utf8: false, included: false`).

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

### /delay/{ms} — Response delay

```
ANY /delay/{ms}
```

Delays the response by the requested number of milliseconds (0–30 000). Useful for testing timeouts, retry logic, and client-side loading states.

```bash
# Delay by 2 seconds
curl http://localhost:4000/delay/2000
# {"requested_ms":2000,"delayed_ms":2000}

# Over the 30-second limit → 400
curl -i http://localhost:4000/delay/60000
```

---

### /stream/{n} — Chunked streaming

```
GET /stream/{n}
```

Streams `n` newline-delimited JSON objects (NDJSON) as chunked transfer encoding, one line per chunk (max 100). Each object contains `line`, `total`, and `timestamp_unix_ms`.

```bash
curl http://localhost:4000/stream/5
# {"line":1,"total":5,"timestamp_unix_ms":...}
# {"line":2,"total":5,"timestamp_unix_ms":...}
# ...
```

---

### /chaos-engineering — Chaos engineering

```
ANY /chaos-engineering
ANY /chaos-engineering/{error_pct}/{mangled_pct}/{latency_pct}/{max_latency_ms}
```

Returns an echo response but randomly injects faults — useful for testing resilience and circuit-breaker logic.

| Fault | What happens |
|---|---|
| Error | A random 4xx/5xx status code is returned |
| Mangled | Response is truncated mid-stream so JSON is syntactically invalid |
| Latency | A random delay up to `max_latency_ms` is added |

**Path parameters** (all integers, 0–100 for percentages, 0–30000 for max latency):

```bash
# 10% errors, 10% mangled, 20% latency up to 2 s (same as defaults)
curl http://localhost:4000/chaos-engineering/10/10/20/2000
```

**Header-based configuration** (percentages as `X-Chaos-*` headers, falls back to defaults):

```bash
curl http://localhost:4000/chaos-engineering \
  -H "X-Chaos-Error-Percentage: 50" \
  -H "X-Chaos-Maximum-Latency: 500"
```

Every response includes a `_chaos` field with the applied parameters and actual latency introduced.

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

To use your own client certificate instead of the generated one, set `LEYWN_MTLS_CERT` (PEM, optionally a full chain) and `LEYWN_MTLS_KEY`. Leywn will serve those at `/auth/mtls/get-client-cert` and automatically add the cert's issuing CA to its trusted list.

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
GET /image/jpeg   (jpg is accepted as alias)
GET /image/gif
GET /image/svg    # dynamic SVG with Leywn branding
GET /image/webp   # PNG re-encoded as WebP (generated at build time)
```

An unknown type returns 400 (`unsupported_image_type`); a known type whose file is not present returns 404 (`image_not_available`).

```bash
curl -o logo.png http://localhost:4000/image/png
curl -o logo.svg http://localhost:4000/image/svg
```

### /image/color — Solid-colour images

```
GET /image/color/{rgb}                  # 64×64 PNG
GET /image/color/{rgb}/{width}/{height} # custom size, max 4096×4096
```

`{rgb}` accepts 3-char (`f00`), 6-char (`ff0000`), or 8-char RGBA (`ff0000cc`) hex strings.

```bash
curl -o red.png http://localhost:4000/image/color/ff0000
curl -o blue.png http://localhost:4000/image/color/0000ff/200/100
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

#### Name, email and colour

```
GET /random/name    # random first name
GET /random/email   # random email address
GET /random/color   # random RGB colour
```

Names and email domains are drawn from `priv/names.txt` and `priv/email_domains.txt`. Mount your own files and point `LEYWN_NAMES_FILE` / `LEYWN_EMAIL_DOMAINS_FILE` at them to customise the output.

```bash
curl http://localhost:4000/random/name
# {"name":"Alice"}

curl http://localhost:4000/random/email
# {"email":"alice4821@example.com"}

curl http://localhost:4000/random/color
# {"hex":"#3a7fc1","r":58,"g":127,"b":193}
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

### /format/* — Format and prettify

```
POST /format/json           # pretty-print a JSON body
POST /format/yaml           # re-indent a YAML body
POST /format/xml            # re-indent an XML body
POST /format/camelCase      # convert the body text to camelCase
POST /format/kebab-case     # convert the body text to kebab-case
POST /format/snake_case     # convert the body text to snake_case
POST /format/toUpper        # uppercase the body text
POST /format/toLower        # lowercase the body text
POST /format/collapse-lines # collapse multiple blank lines into one
```

All format endpoints accept a POST body (limited to `LEYWN_ECHO_MAX_BODY_BYTES`). The three structured endpoints — `json`, `yaml` and `xml` — re-format input of their own type and return 422 if it does not parse. The case and text endpoints operate on the raw body as plain text and return `text/plain`.

```bash
# Pretty-print JSON
curl -s -X POST http://localhost:4000/format/json \
  -H "Content-Type: application/json" \
  -d '{"b":2,"a":1}'

# Re-indent YAML with consistent 2-space indentation
curl -s -X POST http://localhost:4000/format/yaml \
  -H "Content-Type: text/plain" \
  --data-binary $'person:\n    name: Bob\n    age:   25'

# Re-indent XML and add a declaration header
curl -s -X POST http://localhost:4000/format/xml \
  -H "Content-Type: text/plain" \
  -d '<root><child><name>Alice</name></child></root>'

# Convert text between naming conventions
curl -s -X POST http://localhost:4000/format/snake_case -d 'myVariableName'
# my_variable_name

curl -s -X POST http://localhost:4000/format/camelCase -d 'my_variable_name'
# myVariableName
```

---

### /encode and /decode — Codec

```
POST /encode/base64   POST /decode/base64
POST /encode/url      POST /decode/url
POST /encode/hex      POST /decode/hex
POST /encode/rot13    POST /decode/rot13
POST /decode/jwt      # decode JWT header + payload (no sig verification)
```

```bash
curl -s -X POST http://localhost:4000/encode/base64 -d "hello world"
# aGVsbG8gd29ybGQ=

curl -s -X POST http://localhost:4000/decode/base64 -d "aGVsbG8gd29ybGQ="
# hello world

curl -s -X POST http://localhost:4000/encode/hex -d "hello"
# 68656c6c6f

TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyMSJ9.sig"
curl -s -X POST http://localhost:4000/decode/jwt -d "$TOKEN"
```

---

### /hash/* — Hashing

```
POST /hash/sha256
POST /hash/md5
```

Hashes the raw request body and returns the hex digest along with the algorithm name and input byte count.

```bash
curl -s -X POST http://localhost:4000/hash/sha256 -d "hello world"
# {"hash":"b94d27b9...","algorithm":"sha256","input_bytes":11}

curl -s -X POST http://localhost:4000/hash/md5 -d "hello world"
# {"hash":"5eb63bbbe01eeed093cb22bb8f5acdc3","algorithm":"md5","input_bytes":11}
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

### /mocks — Mock REST APIs

```
GET    /mocks                                        # every loaded mock
GET    /mocks/{mock}                                 # collections, counts, write limits
GET    /mocks/{mock}/openapi.json                    # generated OpenAPI for this mock
GET    /docs/mocks/{mock}                            # Swagger UI for this mock

GET    /mocks/{mock}/{collection}                    # list, paged / sorted / filtered
POST   /mocks/{mock}/{collection}                    # create
GET    /mocks/{mock}/{collection}/{id}               # fetch one
PUT    /mocks/{mock}/{collection}/{id}               # replace
PATCH  /mocks/{mock}/{collection}/{id}               # update some fields
DELETE /mocks/{mock}/{collection}/{id}               # delete
GET    /mocks/{mock}/{collection}/{id}/{child}       # related records
```

A mock is a folder holding a `db.json` in the shape [JSONPlaceholder](https://jsonplaceholder.typicode.com/) and [json-server](https://github.com/typicode/json-server) use — top-level keys whose values are arrays of records:

```json
{
  "users":  [{ "id": "a1b2c3d4", "fullName": "Alice Johnson" }],
  "orders": [{ "id": "ord001", "name": "Sugar (50kg)", "userId": "a1b2c3d4" }]
}
```

Every folder under the mocks directory is picked up at startup and served under its own name. Three are bundled:

| Mock | Collections | What it is for |
|---|---|---|
| `marketplace` | `users`, `orders` | The smallest possible example — the dataset from [rest-demo-services](https://github.com/svenwal/rest-demo-services/blob/main/db.json) |
| `accommodations` | `destinations`, `properties`, `availability`, `bookings` | Vacation accommodation search: 24 properties across 8 destinations, with per-week availability and pricing |
| `flightbooking` | `airports`, `flights`, `bookings` | Flight search and booking: 92 flights between 12 airports, with times, seats and fares |

```bash
curl http://localhost:4000/mocks/marketplace/orders/ord001
# {"id":"ord001","name":"Sugar (50kg)","userId":"a1b2c3d4"}
```

`accommodations` and `flightbooking` are separate mocks but are built to work together: every destination carries an `airportCode` that exists as an airport in `flightbooking`, so a travel-agency demo can go from "where" to "how do we get there" across the two. See [the worked example](#a-worked-example-booking-a-vacation) below.

**Adding your own** — no rebuild, no configuration:

```bash
mkdir -p ./mymocks/inventory
echo '{"items":[{"id":1,"sku":"ABC-1","qty":42}]}' > ./mymocks/inventory/db.json

docker run -p 4000:4000 -v "$PWD/mymocks:/app/mocks" \
  -e LEYWN_MOCKS_DIR=/app/mocks svenwal/leywn:latest
```

`inventory` is then served at `/mocks/inventory/items`, with its own OpenAPI at `/mocks/inventory/openapi.json` and a Swagger UI page at `/docs/mocks/inventory` — both linked from the home page. Nothing is generated by hand: the paths come from the collections in the file, the schemas are inferred from the records, and the examples are the records themselves.

A key whose value is a single object rather than an array becomes a read-only single-object resource at `/mocks/{mock}/{key}`.

**Reading** — `_page` and `_limit` page the result, `_sort` and `_order` order it, and any other query parameter filters on the field of that name:

```bash
# Orders belonging to one user
curl 'http://localhost:4000/mocks/marketplace/orders?userId=a1b2c3d4'

# Second page of five, newest name first
curl 'http://localhost:4000/mocks/marketplace/orders?_limit=5&_page=2&_sort=name&_order=desc'

# The same relation, followed automatically
curl http://localhost:4000/mocks/marketplace/users/a1b2c3d4/orders
```

Equality is rarely enough for a real search, so filters also take comparison suffixes — the same ones json-server uses:

| Suffix | Meaning | Example |
|---|---|---|
| `_gte` / `_lte` | at least / at most | `?maxGuests_gte=4` |
| `_gt` / `_lt` | strictly greater / less | `?priceEur_lt=200` |
| `_ne` | not equal | `?type_ne=villa` |
| `_like` | case-insensitive substring | `?name_like=villa` |
| `q` | substring across *every* field | `?q=barcelona` |

Numbers compare numerically and everything else as text — which is what makes `?maxGuests_gte=9` correctly exclude a value of 8, and `?from_gte=2026-09-01&from_lte=2026-09-30` work as a date range, since ISO-8601 values already order lexicographically. `_like` and `q` reach into list fields too, so `?amenities_like=pool` matches a property whose `amenities` array contains it. Neither ever compiles a regex from user input.

Collection reads return at most `LEYWN_MOCK_MAX_PAGE_SIZE` records (default 200); the unpaged total comes back in `X-Total-Count`, alongside `X-Page`, `X-Page-Size` and `X-Total-Pages`. Asking for more than the maximum is a `400` rather than a silent truncation.

Nested routes discover the foreign key from the data (`userId`, `user_id`, `propertyId`, …) and accept exactly the same paging, sorting, search and filter parameters as a plain collection read. A child collection with no field referencing the parent returns `404 relation_not_found` rather than a misleading empty list.

**Writing** — writes work out of the box and behave the way a real REST API does:

```bash
curl -X POST http://localhost:4000/mocks/marketplace/orders \
  -H 'content-type: application/json' \
  -d '{"name":"Rice (10kg)","userId":"a1b2c3d4"}'
# 201, Location: /mocks/marketplace/orders/90abcf84
# {"id":"90abcf84","name":"Rice (10kg)","userId":"a1b2c3d4"}

curl -X PATCH http://localhost:4000/mocks/marketplace/orders/ord001 \
  -H 'content-type: application/json' -d '{"name":"Sugar (100kg)"}'

curl -X DELETE http://localhost:4000/mocks/marketplace/orders/ord002
# returns the record that was removed
```

An `id` is generated when the body does not supply one — continuing the sequence where the file uses integer ids, and a random hex string otherwise. A supplied id that already exists is a `409`. On `PUT` and `PATCH` the id in the path wins, so a body cannot move or rename the record the URL addressed.

> [!IMPORTANT]
> **Writes are a lease, not a store.** Nothing is ever written to the JSON file. Changes are held in memory and **forgotten after `LEYWN_MOCK_ENTRY_TTL_SECONDS`** (default 300), after which the file data reads back unchanged — including deletions, so a deleted record reappears. Restarting Leywn discards everything. This is what makes the endpoints safe to expose: state is reclaimed without anyone having to intervene.

Alongside the expiry, four limits bound what writes can cost. Each has its own status code, so a client can tell them apart:

| Limit | Response | Meaning |
|---|---|---|
| `LEYWN_MOCK_WRITE_RATE_LIMIT` / `..._GLOBAL` | `429` + `Retry-After` | Too many mutating requests, per client and overall |
| `LEYWN_MOCK_MAX_NEW_ENTRIES` / `LEYWN_MOCK_MAX_OVERLAY_BYTES` | `507` | This mock, or the server as a whole, already holds its maximum |
| `LEYWN_MOCK_MAX_BODY_BYTES` | `413` | Body too large |
| `LEYWN_MOCK_MAX_DEPTH` / `LEYWN_MOCK_MAX_KEYS` | `422` | Body nested too deeply, or too wide — a small payload can still be expensive to walk |

Set `LEYWN_MOCK_READONLY=true` to serve `GET` only. Every other method then returns `405` with `Allow: GET`, and the generated OpenAPI omits the write operations entirely rather than documenting endpoints that would refuse.

```bash
docker run -p 4000:4000 -e LEYWN_MOCK_READONLY=true svenwal/leywn:latest
```

#### A worked example: booking a vacation

A travel agency has a party of eight who want a week in Spain in September. The two bundled travel mocks cover the whole flow.

**1. Where can they go?**

```bash
curl 'http://localhost:4000/mocks/accommodations/destinations?country=Spain'
# Barcelona (BCN), Palma de Mallorca (PMI)
```

**2. What sleeps eight in Barcelona?**

```bash
curl 'http://localhost:4000/mocks/accommodations/properties?city=Barcelona&maxGuests_gte=8'
# Barceloneta Beach House — 8 guests, 7 beds, 480 EUR/night
```

**3. Is it free, and what does that week cost?**

```bash
curl 'http://localhost:4000/mocks/accommodations/properties/prop-barceloneta-house/availability?available=true&from_gte=2026-09-08&_limit=4'
# 2026-09-08 → 2026-09-15 | 480 EUR | min 7 nights
```

**4. How do they get there?** The destination's `airportCode` is `BCN`, which is an airport in the other mock:

```bash
curl 'http://localhost:4000/mocks/flightbooking/flights?origin=HAM&destination=BCN&departureDate=2026-09-05&seatsAvailable_gte=8&_sort=priceEur'
# EW7412 Eurowings | 07:15 → 09:50 | 129 EUR | 45 seats
```

**5. Book both.**

```bash
curl -X POST http://localhost:4000/mocks/accommodations/bookings \
  -H 'content-type: application/json' \
  -d '{"propertyId":"prop-barceloneta-house","guestName":"Sven Walther","guests":8,
       "checkIn":"2026-09-08","checkOut":"2026-09-15","nights":7,"totalEur":3445,"status":"confirmed"}'

curl -X POST http://localhost:4000/mocks/flightbooking/bookings \
  -H 'content-type: application/json' \
  -d '{"flightId":"flt-EW7412-20260905","bookingReference":"AG9XK2","passengerName":"Sven Walther",
       "passengers":8,"cabin":"economy","totalEur":1032,"status":"ticketed"}'
```

Both bookings are immediately visible through their relations — `/mocks/flightbooking/flights/flt-EW7412-20260905/bookings` and `/mocks/accommodations/properties/prop-barceloneta-house/bookings` — and both are forgotten again after `LEYWN_MOCK_ENTRY_TTL_SECONDS`, so the demo resets itself for the next run.

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
└── leywn/
    ├── application.ex   # OTP Application — starts HTTP + HTTPS listeners
    ├── router.ex        # Plug.Router — all route definitions and home page HTML
    ├── echo.ex          # Builds the echo response map from a Plug.Conn
    ├── body.ex          # Reads and inspects the request body
    ├── auth.ex          # All authentication handlers (basic, api-key, jwt, mtls)
    ├── mtls.ex          # Generates CA / server / client certificates at startup
    ├── chaos.ex         # Chaos engineering: random error/mangled/latency injection
    ├── random.ex        # UUID, integer, color, name, email, and Lorem Ipsum generators
    ├── logos.ex         # Image serving: file lookup, SVG, WebP, solid-colour PNG generator
    ├── info.ex          # IP address, date, and time helpers
    ├── format.ex        # POST body format/prettify transformations
    ├── codec.ex         # POST body encode/decode operations
    ├── hash.ex          # POST body hashing (SHA-256, MD5)
    ├── yaml.ex          # Minimal pure-Elixir YAML emitter
    ├── cors.ex          # CORS plug — adds Access-Control-* headers
    ├── request_logger.ex# Structured request logging to stdout
    ├── respond.ex       # Content negotiation and JSON/XML serialisation
    ├── servers.ex       # Self-referencing URLs for OpenAPI servers and Insomnia
    ├── insomnia_collection.ex  # Generates the Insomnia v4 collection export
    └── mock/            # Mock REST APIs served from JSON files
        ├── config.ex    # Every LEYWN_MOCK_* limit, in one place
        ├── loader.ex    # Reads the mocks directory once at startup
        ├── store.ex     # In-memory write overlay: TTL leases, entry and byte caps
        ├── rate_limit.ex# Per-IP and global write rate limiting
        ├── data.ex      # Read model: file data with the overlay applied
        ├── inflect.ex   # Collection name -> singular, for foreign keys and schema names
        ├── handler.ex   # Every route under /mocks
        └── openapi.ex   # Renders a mock's OpenAPI from its own data

config/
├── config.exs           # Compile-time defaults
└── runtime.exs          # Runtime configuration from environment variables

priv/
├── openapi.json         # OpenAPI 3.0 specification (served at /openapi.json)
├── names.txt            # name pool for /random/name and /random/email
├── email_domains.txt    # domain pool for /random/email
├── mocks/               # built-in mocks; mount more folders alongside them
│   ├── marketplace/db.json
│   ├── accommodations/db.json
│   └── flightbooking/db.json
├── templates/
│   ├── home.html.eex    # home page, compiled into the router at build time
│   └── mock.html.eex    # per-mock Swagger UI page
└── images/
    ├── leywn.png
    ├── leywn.jpeg
    ├── leywn.gif
    └── leywn.webp       # generated from leywn.png by cwebp during the build
```

**Key dependencies:**

| Package | Purpose |
|---|---|
| `plug_cowboy` | HTTP/HTTPS server |
| `jason` | JSON encoding/decoding |
| `xml_builder_ex` | XML serialisation |
| `tz` | IANA timezone database for `/date` and `/time` (pure Elixir, no runtime dependencies) |
| `yaml_elixir` / `yamerl` | YAML parsing for `/format/yaml` (pure Erlang, no C NIFs) |

Certificate generation uses Erlang's built-in `:public_key` and `:crypto` modules — no external PKI dependencies.

Including everything those pull in transitively, the whole tree is 14 packages. `plug`, `cowboy` and `cowlib` are pinned in `mix.exs` above the floor `plug_cowboy` itself requires, because that floor sits below the releases that carry the 2026 denial-of-service fixes; `mix deps.get` audits the lock against the OSV advisory feed on every build, so a dependency slipping below a fixed version is visible in the build log rather than only in a scanner.

---

## Contributing

Contributions are welcome. Please follow these guidelines:

1. **Fork and branch** — create a feature branch from `main`.
2. **All code in Elixir** — the project is intentionally pure Elixir/OTP for portability and minimal footprint.
3. **Build and test via Docker** — do not assume a local Elixir installation. Always verify with `docker build` and a `docker run` smoke test.
4. **New endpoints** — add the route to `router.ex`, implement logic in a dedicated module under `lib/leywn/`, and add the path to `priv/openapi.json` and the home page listing in `router.ex`.
   Adding a *mock* needs none of that: drop a folder with a `db.json` into the mocks directory and it is served, documented and linked on its own.
5. **Content negotiation** — every endpoint that returns structured data must support both JSON and XML via `Leywn.Respond.send/4`.
6. **Keep it focused** — Leywn is a demo/test tool, not a framework. Avoid adding runtime dependencies unless strictly necessary.

**Reporting issues:** open an issue at <https://github.com/svenwal/leywn/issues>.

---

## License

BSD 2-Clause — see [LICENSE](LICENSE) for details.

---

## AI Disclaimer

This project was created with the assistance of AI (Claude by Anthropic). All code has been reviewed and is provided as-is under the terms of the BSD 2-Clause license.
