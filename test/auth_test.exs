defmodule Leywn.AuthTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @opts Leywn.Router.init([])

  defp call(method, path, headers \\ []) do
    conn(method, path)
    |> Map.update!(:req_headers, &(&1 ++ headers))
    |> Leywn.Router.call(@opts)
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)
  defp basic(user, pass), do: {"authorization", "Basic " <> Base.encode64("#{user}:#{pass}")}

  # ---- /auth/basic-auth ------------------------------------------------------

  test "default credentials are accepted" do
    conn = call(:get, "/auth/basic-auth", [basic("basic", "password")])
    assert conn.status == 200
    body = json(conn)
    assert body["authenticated"] == true
    assert body["auth_type"] == "basic-auth"
    assert body["username"] == "basic"
    # The echo payload is merged in alongside the auth fields
    assert body["method"] == "GET"
  end

  test "wrong password is rejected" do
    conn = call(:get, "/auth/basic-auth", [basic("basic", "wrong")])
    assert conn.status == 401
    assert json(conn)["authenticated"] == false
  end

  test "wrong username is rejected" do
    conn = call(:get, "/auth/basic-auth", [basic("nobody", "password")])
    assert conn.status == 401
  end

  test "missing credentials return 401 with a WWW-Authenticate challenge" do
    conn = call(:get, "/auth/basic-auth")
    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == [~s(Basic realm="Leywn")]
  end

  test "a malformed Authorization header is rejected" do
    for value <- [
          "Basic !!!not-base64!!!",
          "Basic",
          "Bearer abc",
          "Basic " <> Base.encode64("nocolon")
        ] do
      assert call(:get, "/auth/basic-auth", [{"authorization", value}]).status == 401
    end
  end

  test "credentials from the path are enforced" do
    assert call(:get, "/auth/basic-auth/alice/s3cr3t", [basic("alice", "s3cr3t")]).status == 200
    assert call(:get, "/auth/basic-auth/alice/s3cr3t", [basic("alice", "wrong")]).status == 401
    # The default credentials must not open a path-configured endpoint
    assert call(:get, "/auth/basic-auth/alice/s3cr3t", [basic("basic", "password")]).status == 401
  end

  test "a password containing a colon is handled" do
    assert call(:get, "/auth/basic-auth/bob/a:b", [basic("bob", "a:b")]).status == 200
  end

  # ---- /auth/api-key ---------------------------------------------------------

  test "the default api key is accepted" do
    conn = call(:get, "/auth/api-key", [{"apikey", "my-key"}])
    assert conn.status == 200
    body = json(conn)
    assert body["authenticated"] == true
    assert body["auth_type"] == "api-key"
  end

  test "a wrong or missing api key is rejected" do
    assert call(:get, "/auth/api-key", [{"apikey", "wrong"}]).status == 401
    assert call(:get, "/auth/api-key").status == 401
  end

  test "a custom header name and value are enforced" do
    assert call(:get, "/auth/api-key/X-Token/abc123", [{"x-token", "abc123"}]).status == 200
    assert call(:get, "/auth/api-key/X-Token/abc123", [{"x-token", "nope"}]).status == 401
    # Right value, wrong header
    assert call(:get, "/auth/api-key/X-Token/abc123", [{"apikey", "abc123"}]).status == 401
  end

  # ---- /auth/jwt -------------------------------------------------------------

  @jwt_header Base.url_encode64(~s({"alg":"HS256","typ":"JWT"}), padding: false)
  @jwt_payload Base.url_encode64(~s({"sub":"user123","name":"Alice"}), padding: false)
  @jwt "#{@jwt_header}.#{@jwt_payload}.signature"

  test "a structurally valid JWT is accepted and decoded" do
    conn = call(:get, "/auth/jwt", [{"authorization", "Bearer " <> @jwt}])
    assert conn.status == 200
    body = json(conn)
    assert body["authenticated"] == true
    assert body["auth_type"] == "jwt"
    assert body["jwt_header"] == %{"alg" => "HS256", "typ" => "JWT"}
    assert body["claims"] == %{"sub" => "user123", "name" => "Alice"}
  end

  test "a missing or malformed JWT is rejected" do
    assert call(:get, "/auth/jwt").status == 401
    assert call(:get, "/auth/jwt", [{"authorization", "Bearer not.a.jwt"}]).status == 401
    assert call(:get, "/auth/jwt", [{"authorization", "Bearer " <> @jwt_header}]).status == 401
    # Correct token, wrong scheme
    assert call(:get, "/auth/jwt", [{"authorization", "Basic " <> @jwt}]).status == 401
  end

  test "an unauthenticated JWT request advertises Bearer" do
    conn = call(:get, "/auth/jwt")
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="Leywn")]
  end

  # ---- /auth/mtls ------------------------------------------------------------
  # The TLS handshake paths are covered end-to-end in mtls_test.exs; here we only
  # assert that a plain HTTP request without any certificate is refused.

  test "mtls without a client certificate returns 401" do
    conn = call(:get, "/auth/mtls")
    assert conn.status == 401
    assert json(conn)["authenticated"] == false
  end

  test "the demo client certificate and key are downloadable" do
    conn = call(:get, "/auth/mtls/get-client-cert")
    assert conn.status == 200
    body = json(conn)
    assert body["cert_pem"] =~ "BEGIN CERTIFICATE"
    assert body["key_pem"] =~ "PRIVATE KEY"
  end
end
