# Changelog

All notable changes to Leywn are documented in this file.

## [1.1.0-beta2] - 2026-08-14

A dependency-only release on top of `1.1.0-beta1`: every package the OSV advisory feed flagged is now on a fixed version, and the release carries no vulnerable dependency that has a fix available upstream. No endpoint behaviour changes.

  ### Dependencies
  Hex audits the lock file against the OSV advisory feed on every `mix deps.get`, and the build log had grown a list of vulnerable packages. All of them are now on fixed releases, and the tree shrank from 23 packages to 14 in the process.
  - **`plug` 1.19.1 → 1.20.3** — closes four advisories, three of which are reachable from an unauthenticated request against Leywn: quadratic-time decoding of nested query and body parameters (CVE-2026-54892, HIGH), unbounded buffer accumulation while parsing multipart headers (CVE-2026-8468, HIGH), and a multipart `:length` limit that was not charged for part headers, allowing unbounded temp-file creation (CVE-2026-56814)
  - **`cowboy` 2.14.2 → 2.18.0, `cowlib` 2.16.0 → 2.19.0** — the `max_headers` limit could be bypassed with duplicate header names (CVE-2026-65624), chunk-size hex digits were unbounded and decoded in quadratic time (CVE-2026-7790, HIGH), and HPACK/QPACK prefixed integers decoded without a bound (CVE-2026-59248, HIGH). Each is a memory or CPU exhaustion path in the request parser, which is the one piece of code every request reaches before any Leywn code runs
  - **`plug_cowboy` 2.8.0 → 2.9.0** — HTTP/2's `:scheme` pseudo-header was converted to an atom, so a caller could exhaust the atom table and bring the VM down (CVE-2026-32688, HIGH)
  - **`tzdata` replaced by `tz` 0.28.2** — `tzdata` depends on `hackney`, which carries ten open advisories with no fix on the 1.x line; the fixes land in `hackney` 4.x, which `tzdata`'s `~> 1.17` requirement cannot accept. `hackney` existed here only for `tzdata`'s auto-update path, which Leywn had already disabled, so an HTTP client and its seven transitive dependencies were shipped in the release to be never called. `tz` provides the same IANA database as a pure-Elixir library with no runtime dependencies and no network access of its own, and is configured the same way (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`). `/date/{tz}` and `/time/{tz}` are unchanged, including their `404` for an unknown zone
  - **`plug` and `cowboy`/`cowlib` are now direct dependencies** pinned above the floor `plug_cowboy` accepts (`~> 1.18` and `~> 2.7` respectively both resolve to versions predating these fixes), so a fresh resolution cannot quietly land back on a vulnerable release
  - Also picked up: `jason` 1.4.5, `plug_crypto` 2.2.0, `telemetry` 1.4.2, `ranch` 2.2.1, `yaml_elixir` 2.12.2
  - **Two `cowlib` advisories remain open upstream** and have no fixed release at any version: CVE-2026-43966 (MEDIUM, response splitting in `cow_http_struct_hd:escape_string/2`) and CVE-2026-43969 (LOW, cookie header injection in `cow_cookie:cookie/1`). Both are in encoders used when acting as an HTTP *client* or when emitting structured headers, and neither function is referenced anywhere in Cowboy 2.18.0 or Plug 1.20.3 — `cowlib` is present as Cowboy's parsing library, and the affected code is never reached from a request Leywn serves. They will still show in an audit until upstream ships a fix

  ### Changed
  - Version bumped to `1.1.0-beta2` in `mix.exs` and `openapi.json`
  - `config/config.exs` configures `Tz.TimeZoneDatabase` as the time zone database; the `tzdata` autoupdate setting went with the dependency
  - The full test suite (287 tests) passes unchanged against the new dependency versions

  ### Documentation
  - README: the dependency table lists `tz` in place of `tzdata`, with a note on the 14-package tree, the pinned `plug`/`cowboy`/`cowlib` floors and the OSV audit that runs on every build

---

## [1.1.0-beta1] - 2026-08-14

  ### Added
  - **Mocking — `/mocks`** — Leywn now serves mock REST APIs from plain JSON files. A directory (`LEYWN_MOCKS_DIR`, default `priv/mocks`) holds one subfolder per mock; each folder's `db.json` — in the shape JSONPlaceholder and json-server use — is served as `/mocks/{folder_name}`. Adding a mock is adding a folder: nothing is registered, configured or rebuilt, so a mock can simply be mounted into the container
  - **Three bundled mocks** — `marketplace`, the dataset from [rest-demo-services](https://github.com/svenwal/rest-demo-services/blob/main/db.json) (10 users, 27 orders); `accommodations`, a vacation accommodation search with 8 destinations, 24 properties carrying the metadata a search needs (bedrooms, beds, bathrooms, `maxGuests`, price, rating, amenities), 192 per-week availability rows and seeded bookings; and `flightbooking`, a flight search and booking service with 12 airports and 92 flights carrying times, durations, fares and seat counts. The latter two are separate services but are built to be used together — every destination's `airportCode` exists as an airport in `flightbooking` — so a travel agency can search by location and party size and then book both halves of a trip
  - **Comparison filters** — `_gte`, `_lte`, `_gt`, `_lt`, `_ne` and `_like` alongside plain equality, following json-server's convention. Numbers compare numerically and everything else as text, so `?maxGuests_gte=9` correctly excludes 8, and `?from_gte=2026-09-01&from_lte=2026-09-30` works as a date range because ISO-8601 values already order lexicographically. Equality alone could not express either
  - **`?q=` full-text search** — a case-insensitive substring match across every field of a record. It and `_like` also reach into list fields, so `?amenities_like=pool` matches a property whose `amenities` array contains it. Neither ever compiles a regex from caller input, and `q` is capped at 128 characters because the needle is compared against every value of every record
  - **Full CRUD per collection** — `GET`/`POST` on `/mocks/{mock}/{collection}` and `GET`/`PUT`/`PATCH`/`DELETE` on `/mocks/{mock}/{collection}/{id}`. `POST` returns `201` with a `Location` header and generates an `id` when the body has none, continuing the sequence where the file uses integer ids; a supplied id that already exists is a `409`. On `PUT` and `PATCH` the id in the path wins, so a body cannot move or rename the record the URL addressed
  - **Query support on reads** — `_page` / `_limit` page, `_sort` / `_order` order, and any other query parameter filters on the field of that name. The unpaged total is returned in `X-Total-Count` alongside `X-Page`, `X-Page-Size` and `X-Total-Pages`, all added to `Access-Control-Expose-Headers` so browsers can read them
  - **Relation following** — `/mocks/{mock}/{collection}/{id}/{child}` returns the related records (`/users/{id}/orders` matches on `userId`). The foreign key is discovered from the data, so `user_id` works too; a child collection with no field referencing the parent is a `404` rather than a misleading empty list. Nested results go through the same pipeline as a plain collection read, so they page, sort, search and filter identically — a relation is often the larger of the two sides, and leaving it unpaged would have been the one unbounded read left in the feature
  - **Proper singularisation** — `Leywn.Mock.Inflect` turns a collection name into its singular for foreign-key discovery, XML root elements and generated schema names. Naive `s`-stripping would look for `propertieId` in a `properties` collection and find nothing, and would render `status` as `statu`. Irregular plurals (`-ies`, `-sses`, `-ches`, `-xes`) and words that merely end in `s` are all handled, and nested routes still try both the derived and the naive form
  - **A generated OpenAPI per mock** — `/mocks/{mock}/openapi.json`, with a Swagger UI page at `/docs/mocks/{mock}`. Three mock folders therefore mean four OpenAPI documents: the main one plus one per mock. Nothing in them is hand-maintained — paths come from the collections the file declares, schemas are inferred from the records, and examples are real records. Each document describes the installation as it is actually running: write operations are absent under `LEYWN_MOCK_READONLY=true`, XML response variants under `LEYWN_ONLY_JSON=true`
  - **Home page links** — every loaded mock appears on the home page, and each mock page links back to the main docs and across to its siblings
  - **Single-object resources** — a top-level key whose value is an object rather than an array is served read-only at `/mocks/{mock}/{key}`
  - **Insomnia collection covers the mocks** — the `Mocks` folder is generated from whatever is mounted, with a list, fetch, create, update and delete request per collection and example bodies taken from real records
  - **`GET /mocks` and `GET /mocks/{mock}`** — discovery endpoints listing the loaded mocks and, per mock, its collections, record counts and the write limits in force. `/mocks/{mock}` deliberately does not return the whole dataset: a mounted file may be large, and re-encoding all of it per request is an amplification target
  - **Startup banner lists the loaded mocks** and whether they are writable

  ### Security
  Mock writes are the only part of Leywn that accepts input and keeps state between requests, so they are bounded on every axis an anonymous caller can push on. Each limit has its own status code so a client can tell them apart.
  - **State is a lease, not a store** — every change is forgotten after `LEYWN_MOCK_ENTRY_TTL_SECONDS` (default 300), after which the file data reads back unchanged. This is the property that makes the endpoints safe to leave exposed: whatever an attacker manages to write is reclaimed without operator involvement. Deletions expire too, so a deleted record reappears
  - **Write rate limiting** — `LEYWN_MOCK_WRITE_RATE_LIMIT` (default 60/min per client IP) and `LEYWN_MOCK_WRITE_RATE_LIMIT_GLOBAL` (default 600/min overall), returning `429` with `Retry-After`. The global ceiling is what actually bounds the write rate: an attacker with a thousand source addresses would otherwise have a thousand times the per-IP budget. Counters use the window as part of the ETS key and `:ets.update_counter/4`, so a new window starts by counting into a new key rather than by resetting an old one — no read-modify-write race, and no process in the request path
  - **Bounded rate-limiter memory** — the limiter's own table is a memory surface, one row per source address, and an attacker who controls `X-Forwarded-For` under `LEYWN_TRUST_FORWARD=true` controls how many rows exist. `LEYWN_MOCK_RATE_BUCKETS` (default 10 000) caps the per-IP rows; past that, new addresses fall back to the global ceiling alone — the stricter limit is the one that survives. Forwarded values are truncated to 64 bytes before becoming part of a key
  - **Entry and byte caps** — `LEYWN_MOCK_MAX_NEW_ENTRIES` (default 100 per mock) and `LEYWN_MOCK_MAX_OVERLAY_BYTES` (default 1 MiB across all mocks), returning `507`. Both are needed: an entry count alone says nothing about memory, since a hundred 16 KiB entries per mock is megabytes once several are mounted
  - **Body size, depth and width caps** — `LEYWN_MOCK_MAX_BODY_BYTES` (default 16 384) returning `413`, and `LEYWN_MOCK_MAX_DEPTH` (16) / `LEYWN_MOCK_MAX_KEYS` (100) returning `422`. Byte size alone does not bound cost: Jason imposes no depth limit of its own, so a body well inside the size cap can still nest deeply enough that walking and re-encoding it costs far more than its length suggests
  - **Capped collection reads** — a collection returns at most `LEYWN_MOCK_MAX_PAGE_SIZE` records (default 200) and a larger `_limit` is a `400` rather than a silent truncation, closing the cheap-request/expensive-response asymmetry a large mounted file would otherwise create. `LEYWN_MOCK_MAX_FILTERS` (default 10) bounds how many filters one read may apply
  - **Datasets are read once at startup**, never per request, so a large mounted file cannot be turned into an amplification target. `LEYWN_MOCK_MAX_FILE_BYTES` (8 MiB, checked via the file's metadata before a byte is read), `LEYWN_MOCK_MAX_MOCKS` (50) and `LEYWN_MOCK_MAX_COLLECTIONS` (100) bound what that load can cost
  - **Path safety** — mock and collection names are restricted to characters that cannot mean anything else in a path, so `..`, separators and dotfiles are rejected before a name is ever used as a lookup key. Symlinks in the mocks directory are not followed (`lstat`, not `stat`), so the directory layout cannot redirect which files are read. `openapi.json` is reserved as a collection name rather than being silently shadowed
  - **`LEYWN_MOCK_READONLY=true`** — serves `GET` only, with `405` and `Allow: GET` on everything else, for installations that want no write surface at all

  ### Changed
  - **`Leywn.Servers` extracted from the router** — the logic deciding which address a self-referencing URL should name now lives in one module. The main spec is no longer the only one, and two copies of "which address did the caller actually reach us on" would have drifted apart
  - **Test suite expanded from 180 to 287 tests** — `test/mock_test.exs` covers loading, path-traversal rejection, reads, paging, sorting, every comparison operator, full-text search, relations, singularisation, XML negotiation, every write verb, body validation, each limit in turn, TTL expiry, read-only mode and the generated documents, plus a check that the two travel mocks stay consistent with each other on airport codes
  - Version bumped to `1.1.0-beta1` in `mix.exs` and `openapi.json`

  ### Documentation
  - OpenAPI: new `Mock` tag with all seven mock paths, each documenting the limits it enforces and the status code that reports them; new `ErrorResponse`, `MockIndex` and `MockOverview` schemas
  - README: new `/mocks` section covering the file layout, the three bundled mocks, mounting your own, reading (including the comparison-operator table), writing, and the full limit table; a worked travel-agency example running the whole search-and-book flow across both travel mocks; new "Mock configuration" table with all sixteen `LEYWN_MOCK_*` variables; code structure and contributing notes updated
  - `sub-docs/endpoints/mock.md` added

---

## [1.0.0] - 2026-07-31

First generally available release.

  ### Security
  - **XML element-name injection** — map keys become XML element names, and on `/echo`, `/anything`, `/chaos-engineering` and the `/auth/*` endpoints those keys come straight from query-parameter and header names. A request such as `/echo?a><injected>x</injected><b=1` with `Accept: application/xml` previously emitted the angle brackets as markup, injecting arbitrary elements into the response and breaking every XML parser. Element names are now restricted to legal XML `NameChar`s, with an `_` prefix where a name could not legally start an element
  - **Chaos latency denial of service** — the `X-Chaos-*` headers were read without any validation, so `X-Chaos-Maximum-Latency: 600000` made the server sleep for up to ten minutes per request; against the 1 000-connection cap that is trivially exhaustible. Header parameters are now validated against the same ranges as the path parameters and rejected with `400` before any sleep occurs
  - **Timing-safe credential comparison** — `/auth/basic-auth` and `/auth/api-key` compared the presented username, password and key with `==`, which short-circuits on the first differing byte. Comparison now runs over SHA-256 digests via `:crypto.hash_equals/2`, so neither the value nor its length leaks through response timing
  - **Swagger UI pinned with Subresource Integrity** — the home page loaded `swagger-ui-dist@5` from unpkg with no integrity hash, so any future `5.x` release or a compromise of the CDN would execute unreviewed script on the page. Both assets are now pinned to `5.32.11` and carry `integrity` + `crossorigin` attributes
  - **Half-configured TLS no longer ignored** — setting only one of `LEYWN_TLS_SERVER_CRT` / `LEYWN_TLS_SERVER_KEY` silently fell back to a generated self-signed certificate. Startup now aborts with an explicit error, as documented
  - **Generated server certificate carries a subjectAltName** — the certificate had only `CN=localhost`, which clients have not accepted for hostname verification since RFC 6125, so it could never be validated even by a client trusting the demo CA. It now includes `DNS:localhost`, `IP:127.0.0.1` and `IP:::1`
  - **`Vary: Origin`** — sent whenever `LEYWN_CORS_ORIGIN` names a specific origin, so an intermediary cache cannot serve one origin's response, and its `Access-Control-Allow-Origin`, to another
  - **Empty `LEYWN_MTLS_IN_HEADER`** — an exported-but-empty value took the header branch with no header name, failing every `/auth/mtls` request; it is now treated as unset

  ### Fixed
  - **Self-referencing URLs were wrong on HTTPS** — the HTTPS listener negotiates HTTP/2 via ALPN, and HTTP/2 has no `Host` header. Reading the raw header made the OpenAPI `servers` entry, the Insomnia button and the collection `base_url` all fall back to `http://localhost:<HTTP port>` on every HTTPS request. These now derive from `conn.host` / `conn.port`, which Plug populates for both protocol versions
  - **`/image/webp` returned 500 when the file was absent** — `send_file/3` raised on the missing path. A supported type with no file now returns `404 image_not_available`; an unsupported type still returns `400 unsupported_image_type`
  - **Single-valued headers in `/echo` are no longer wrapped in an array** — `sub-docs/endpoints/echo.md` has always required a header sent once to be returned as a plain value. Only genuinely repeated headers are now arrays
  - **CI never ran the test suite** — the workflow only ran `docker build --target test`, and `CMD` is not executed during a build, so nothing but `mix format --check-formatted` actually gated a merge. The image is now tagged and the suite run in a container
  - **`OPTIONS` requests were never logged** — the CORS plug halts preflights, and the request logger was registered after it. The logger now runs first, so every request reaches the log as `CLAUDE.md` requires
  - **Binary images were labelled `charset=utf-8`** — `put_resp_content_type/2` appends a character set, which is meaningless on a PNG, JPEG, GIF or WebP payload. The content type is now set verbatim
  - **Insomnia `/decode/rot13` example was wrong** — `Uryyb, Yrjla!` decodes to `Lewyn`; corrected to `Uryyb, Yrlja!`
  - **Insomnia collection was missing `/image/webp`**

  ### Changed
  - **Name and domain files are read once and cached** — `/random`, `/random/name` and `/random/email` re-read and re-parsed their backing file on every request (`/random/email` twice). They are now parsed once into `:persistent_term`; replacing the files requires a restart
  - **Test suite expanded from 112 to 180 tests** — added coverage for `/echo`, `/anything`, `/status/{code}`, `/uuid`, `/guuid`, `/random/int`, `/random/uint`, `/ip`, `/date`, `/time`, `/auth/basic-auth`, `/auth/api-key`, `/auth/jwt`, `/image/webp`, XML content negotiation, `LEYWN_ONLY_JSON` and chaos header validation, none of which had any tests
  - **Test modules run concurrently** and the deprecated `use Plug.Test` was replaced with explicit imports; the suite compiles without warnings
  - **`cwebp` added to the Docker test stage** so `/image/webp` is exercised under the same conditions as production
  - Removed the unused `Leywn.Format.transform_keys/2` left behind by the plain-text case conversion change, and an unused variable in `router.ex` — the project now compiles warning-free
  - `SwaggerUIStandalonePreset` removed from the Swagger UI config; it ships in a bundle the page does not load, so it only ever contributed `undefined`

  ### Documentation
  - OpenAPI: documented `/`, `/docs` and `/openapi.json`, which were served but absent from the spec; added the `404` response on `/image/{type}`; corrected the `EchoResponse.headers` schema and every echo example to the new header shape; described the enforced ranges on the `X-Chaos-*` parameters
  - README: corrected the `/format/*` section, which still described `yaml`/`xml` as JSON converters and the case endpoints as JSON key transformers, and still used the pre-1.0 `/format/snake-case` path; refreshed the `/health` version example; documented `LEYWN_CORS_ORIGIN`, `LEYWN_EXTERNAL_HTTP_URL`, `LEYWN_EXTERNAL_HTTPS_URL`, `LEYWN_NAMES_FILE` and `LEYWN_EMAIL_DOMAINS_FILE`; documented `/docs`, `/openapi.json`, `/request-collection`, `/random/name`, `/random/email` and `/random/color`; corrected the image size to ~38 MB
  - `sub-docs/endpoints`: added `chaos.md`, which had no requirement document; corrected `cors.md` (wildcard allow-headers), `format.md` (plain-text case conversion, `snake_case` path), `delay.md` and `stream.md` (reject rather than clamp), `image.md` (build-time WebP) and `health.md` (version example)

---

## [1.0.0-rc2] - 2026-04-30

  ### Changed
  - **OpenAPI: `/echo/{path}` and `/anything/{path}` removed** — sub-path support is now documented inline on `/echo` and `/anything` instead of as separate operations
  - **OpenAPI: alphabetical operation ordering enforced** — `operationsSorter: 'alpha'` added to Swagger UI config so operations are always sorted alphabetically within each tag group
  - **GitHub Actions: Node.js 24 compatibility** — all actions in `build-and-push.yaml` updated to their latest versions (`actions/checkout@v4`, `docker/*@v3`, `docker/build-push-action@v6`)
  - **`/format/camelCase`, `/format/kebab-case`, and `/format/snake_case` now accept plain text** — previously required a JSON object and transformed its keys; now convert the raw body string to the target case and return `text/plain`. Existing camelCase/snake_case/kebab-case input all work; no JSON parsing involved.
  - **Homepage extracted into an EEx template** — `priv/templates/home.html.eex` now holds all HTML/CSS; `router.ex` compiles it at build time via `EEx.function_from_file`, keeping the router free of inline markup.
  - **Insomnia collection corrected** — `/format/snake_case` entry had the wrong URL (`/format/snake-case`); both `/format/kebab-case` and `/format/snake_case` examples updated to use `text/plain` bodies that reflect plain-text conversion.
  - **Insomnia collection: RFC 8693 token exchange entry added** — a second `/auth/jwt/exchange` request now demonstrates the `POST application/x-www-form-urlencoded` flow with `grant_type`, `subject_token`, `subject_token_type`, `audience`, and `scope` fields alongside the existing Bearer variant; `Content-Type: application/x-www-form-urlencoded` is set explicitly in the headers array so the correct server path is taken regardless of Insomnia version.
  - **Chaos test made deterministic** — the `path params appear in _chaos meta` test previously used `5/15/25/1000`, giving a ~20 % per-run failure rate; replaced with `0/0/0/500` (zero error/mangled/latency percentages guarantee a 200 response with no sleep while still verifying `maximum_latency_ms` is reflected in meta).
  - **Startup banner** — on launch, Leywn now prints the version and listening ports to stdout, followed by a list of all `LEYWN_*` environment variables that are explicitly set (PEM-valued vars `LEYWN_TLS_SERVER_KEY`, `LEYWN_TLS_SERVER_CRT`, `LEYWN_MTLS_CERT`, and `LEYWN_MTLS_KEY` are shown as `<set>` rather than their content); if no variables are set a single "using defaults" line is printed instead.
  - Version bumped to `1.0.0-rc2` in `mix.exs` and `openapi.json`

---

## [1.0.0-rc1] - 2026-04-24

  ### Added
  - **RFC 8693 Token Exchange** — `POST /auth/jwt/exchange` now supports `application/x-www-form-urlencoded` requests with `grant_type=urn:ietf:params:oauth:grant-type:token-exchange`; returns a standards-compliant response (`access_token`, `issued_token_type`, `token_type`, `expires_in`); optional `audience` and `scope` parameters are forwarded as claims
  - **Homepage GitHub and Docker Hub buttons** — upper-right header now links to the GitHub repository and Docker Hub image page alongside the existing Insomnia button

  ### Changed
  - **`/format/snake-case` renamed to `/format/snake_case`** — path now uses an underscore to match the output convention
  - **`/format/camelCase`, `/format/kebab-case`, `/format/snake_case`** — OpenAPI descriptions corrected: these endpoints transform generic text, not JSON exclusively
  - **OpenAPI endpoint ordering** — all paths are now sorted alphabetically within each tag group
  - **OpenAPI examples** — every operation now carries a real-world request example and a computed response example (e.g. `encode/rot13` request `"Hello Leywn"` → response `"Uryyb Yrlja"`)
  - **Swagger UI** — tags start collapsed (`docExpansion: none`) for a cleaner first-load experience
  - Version bumped to `1.0.0-rc1` in `mix.exs` and `openapi.json`

---

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
