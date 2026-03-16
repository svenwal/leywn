#!/usr/bin/env bash
# Leywn endpoint smoke tests
# Usage: ./test_endpoints.sh [host] [port] [tls_port]

HOST="${1:-localhost}"
PORT="${2:-4000}"
TLS_PORT="${3:-4443}"
BASE="http://${HOST}:${PORT}"
TLS_BASE="https://${HOST}:${TLS_PORT}"

PASS=0
FAIL=0

check() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label"
    echo "        expected to find: $expected"
    echo "        got: $(echo "$actual" | head -3)"
    ((FAIL++))
  fi
}

check_code() {
  local label="$1"
  local expected_code="$2"
  local actual_code="$3"
  if [ "$actual_code" = "$expected_code" ]; then
    echo "  PASS: $label (HTTP $actual_code)"
    ((PASS++))
  else
    echo "  FAIL: $label (expected HTTP $expected_code, got HTTP $actual_code)"
    ((FAIL++))
  fi
}

echo ""
echo "=============================="
echo " Leywn Endpoint Smoke Tests"
echo " Target: $BASE  |  TLS: $TLS_BASE"
echo "=============================="

# ---------------------------------------------------------------------------
echo ""
echo "--- /echo ---"

r=$(curl -s "$BASE/echo")
check "GET /echo returns path" '"path":"/echo"' "$r"
check "GET /echo returns method GET" '"method":"GET"' "$r"
check "GET /echo returns host" '"host":"'"$HOST"'"' "$r"

r=$(curl -s "$BASE/echo/foo/bar?x=1")
check "GET /echo/foo/bar returns subpath" '"path":"/echo/foo/bar"' "$r"
check "GET /echo/foo/bar captures query param x" '"x":"1"' "$r"

r=$(curl -s -X POST "$BASE/echo" -H "Content-Type: application/json" -d '{"hello":"world"}')
check "POST /echo captures body" 'hello.*world' "$r"
check "POST /echo method is POST" '"method":"POST"' "$r"

r=$(curl -s "$BASE/echo" -H "Accept: application/xml")
check "GET /echo returns XML when requested" '<echo>' "$r"

# ---------------------------------------------------------------------------
echo ""
echo "--- /status ---"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/200")
check_code "GET /status/200" "200" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/201")
check_code "GET /status/201" "201" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/404")
check_code "GET /status/404" "404" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/500")
check_code "GET /status/500" "500" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/204")
check_code "GET /status/204 (no body)" "204" "$code"

r=$(curl -s "$BASE/status/999")
check "GET /status/999 returns error" "invalid_status_code" "$r"
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status/999")
check_code "GET /status/999 returns 400" "400" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "--- /auth/basic-auth ---"

r=$(curl -s -u basic:password "$BASE/auth/basic-auth")
check "basic-auth correct creds: authenticated=true" '"authenticated":true' "$r"
check "basic-auth correct creds: username in response" '"username":"basic"' "$r"
check "basic-auth correct creds: echo path present" '"path":"/auth/basic-auth"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" -u wrong:creds "$BASE/auth/basic-auth")
check_code "basic-auth wrong creds returns 401" "401" "$code"

r=$(curl -s -u alice:secret "$BASE/auth/basic-auth/alice/secret")
check "basic-auth custom creds: authenticated=true" '"authenticated":true' "$r"
check "basic-auth custom creds: username=alice" '"username":"alice"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" -u alice:wrong "$BASE/auth/basic-auth/alice/secret")
check_code "basic-auth custom creds wrong password returns 401" "401" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "--- /auth/api-key ---"

r=$(curl -s -H "apikey: my-key" "$BASE/auth/api-key")
check "api-key correct: authenticated=true" '"authenticated":true' "$r"
check "api-key correct: echo path present" '"path":"/auth/api-key"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/auth/api-key")
check_code "api-key missing header returns 401" "401" "$code"

r=$(curl -s -H "x-token: secret123" "$BASE/auth/api-key/x-token/secret123")
check "api-key custom header: authenticated=true" '"authenticated":true' "$r"
check "api-key custom header: header name in response" '"header":"x-token"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" -H "x-token: wrongval" "$BASE/auth/api-key/x-token/secret123")
check_code "api-key custom header wrong value returns 401" "401" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "--- /auth/jwt ---"

JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

r=$(curl -s -H "Authorization: Bearer $JWT" "$BASE/auth/jwt")
check "jwt valid: authenticated=true" '"authenticated":true' "$r"
check "jwt valid: claims present" '"claims"' "$r"
check "jwt valid: jwt_header present" '"jwt_header"' "$r"
check "jwt valid: echo path present" '"path":"/auth/jwt"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/auth/jwt")
check_code "jwt missing token returns 401" "401" "$code"

code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer notajwt" "$BASE/auth/jwt")
check_code "jwt malformed token returns 401" "401" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "--- /auth/mtls ---"

r=$(curl -s "$BASE/auth/mtls/get-client-cert")
check "get-client-cert returns cert_pem" '"cert_pem"' "$r"
check "get-client-cert returns key_pem" '"key_pem"' "$r"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/auth/mtls")
check_code "mtls without cert on plain HTTP returns 401" "401" "$code"

# Download client cert and test mTLS over HTTPS
CERT_JSON=$(curl -s "$BASE/auth/mtls/get-client-cert")
CERT_PEM=$(echo "$CERT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['cert_pem'])")
KEY_PEM=$(echo "$CERT_JSON"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['key_pem'])")
echo "$CERT_PEM" > /tmp/leywn_test_client.pem
echo "$KEY_PEM"  > /tmp/leywn_test_client.key

r=$(curl -sk --cert /tmp/leywn_test_client.pem --key /tmp/leywn_test_client.key "$TLS_BASE/auth/mtls")
check "mtls with client cert: authenticated=true" '"authenticated":true' "$r"
check "mtls with client cert: client_dn present" '"client_dn"' "$r"
check "mtls with client cert: client_ca present" '"client_ca"' "$r"
check "mtls with client cert: echo path present" '"path":"/auth/mtls"' "$r"

rm -f /tmp/leywn_test_client.pem /tmp/leywn_test_client.key

# ---------------------------------------------------------------------------
echo ""
echo "--- /image ---"

for type in png jpeg gif; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/image/$type")
  check_code "GET /image/$type returns 200" "200" "$code"
  ct=$(curl -s -o /dev/null -w "%{content_type}" "$BASE/image/$type")
  check "GET /image/$type has correct content-type" "image/$type" "$ct"
done

r=$(curl -s "$BASE/image/bmp")
check "GET /image/bmp returns unsupported error" "unsupported_image_type" "$r"
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/image/bmp")
check_code "GET /image/bmp returns 400" "400" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "--- / and /openapi.json ---"

code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/")
check_code "GET / returns 200" "200" "$code"
ct=$(curl -s -o /dev/null -w "%{content_type}" "$BASE/")
check "GET / returns HTML" "text/html" "$ct"

r=$(curl -s "$BASE/openapi.json")
check "GET /openapi.json contains openapi version" '"openapi"' "$r"
check "GET /openapi.json contains paths" '"paths"' "$r"

# ---------------------------------------------------------------------------
echo ""
echo "--- 404 ---"

r=$(curl -s "$BASE/nonexistent")
check "unknown path returns not_found error" '"not_found"' "$r"
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/nonexistent")
check_code "unknown path returns 404" "404" "$code"

# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo " Results: $PASS passed, $FAIL failed"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
