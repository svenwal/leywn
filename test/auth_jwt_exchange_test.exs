defmodule Leywn.AuthJwtExchangeTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  @opts Leywn.Router.init([])

  # Build a minimal unsigned JWT for testing — signature is not verified by Leywn.
  defp make_jwt(claims \\ %{"sub" => "user1"}) do
    header = Base.url_encode64(Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)
    header <> "." <> payload <> ".fakesig"
  end

  defp post_form(path, body) do
    conn(:post, path, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Leywn.Router.call(@opts)
  end

  defp bearer_exchange(token) do
    conn(:post, "/auth/jwt/exchange")
    |> put_req_header("authorization", "Bearer #{token}")
    |> Leywn.Router.call(@opts)
  end

  # ---- Bearer mode -----------------------------------------------------------

  test "Bearer mode returns 200 with exchanged_token" do
    conn = bearer_exchange(make_jwt())
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["authenticated"] == true
    assert is_binary(body["exchanged_token"])
    assert body["claims"]["iss"] == "leywn"
  end

  test "Bearer mode without token returns 401" do
    conn = conn(:post, "/auth/jwt/exchange") |> Leywn.Router.call(@opts)
    assert conn.status == 401
  end

  test "Bearer mode preserves incoming claims" do
    conn = bearer_exchange(make_jwt(%{"sub" => "alice", "role" => "admin"}))
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["claims"]["sub"] == "alice"
    assert body["claims"]["role"] == "admin"
  end

  # ---- RFC 8693 mode ---------------------------------------------------------

  test "RFC 8693: valid request returns access_token" do
    token = make_jwt()

    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => token,
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    assert is_binary(body["access_token"])
    assert body["issued_token_type"] == "urn:ietf:params:oauth:token-type:jwt"
    assert body["token_type"] == "Bearer"
    assert body["expires_in"] == 3600
  end

  test "RFC 8693: access_token type accepted as subject_token_type" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => make_jwt(),
        "subject_token_type" => "urn:ietf:params:oauth:token-type:access_token"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 200
  end

  test "RFC 8693: audience is propagated as aud claim" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => make_jwt(),
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt",
        "audience" => "my-service"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    [_header, payload, _sig] = String.split(body["access_token"], ".")
    {:ok, claims_json} = Base.url_decode64(payload, padding: false)
    {:ok, claims} = Jason.decode(claims_json)
    assert claims["aud"] == "my-service"
  end

  test "RFC 8693: scope is propagated as scope claim" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => make_jwt(),
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt",
        "scope" => "read write"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 200
    {:ok, body} = Jason.decode(conn.resp_body)
    [_header, payload, _sig] = String.split(body["access_token"], ".")
    {:ok, claims_json} = Base.url_decode64(payload, padding: false)
    {:ok, claims} = Jason.decode(claims_json)
    assert claims["scope"] == "read write"
  end

  test "RFC 8693: wrong grant_type returns 400 invalid_request" do
    params =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "subject_token" => make_jwt(),
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "invalid_request"
  end

  test "RFC 8693: missing subject_token returns 400" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "invalid_request"
  end

  test "RFC 8693: unsupported subject_token_type returns 400" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => make_jwt(),
        "subject_token_type" => "urn:ietf:params:oauth:token-type:saml2"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["error"] == "invalid_request"
  end

  test "RFC 8693: malformed subject_token returns 400" do
    params =
      URI.encode_query(%{
        "grant_type" => "urn:ietf:params:oauth:grant-type:token-exchange",
        "subject_token" => "not.a.jwt.at.all.really",
        "subject_token_type" => "urn:ietf:params:oauth:token-type:jwt"
      })

    conn = post_form("/auth/jwt/exchange", params)
    assert conn.status == 400
  end
end
