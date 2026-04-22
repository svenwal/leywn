defmodule Leywn.MTLSTest do
  use ExUnit.Case

  @tls_port 4443
  @host ~c"localhost"
  @path "/auth/mtls"

  # Test 1: No client certificate is presented.
  # The TLS handshake must succeed (fail_if_no_peer_cert is false), but the
  # endpoint must return 401 because no cert was provided.
  test "no client certificate returns 401" do
    {:ok, status, _body} = https_get(@host, @tls_port, @path, verify: :verify_none)
    assert status == 401
  end

  # Test 2: A wrong client certificate (self-signed, not from our CA).
  # The server's verify_fun must reject it, causing a TLS-level failure.
  test "wrong (self-signed) client certificate is rejected at TLS level" do
    wrong_key = :public_key.generate_key({:namedCurve, :secp256r1})
    wrong_cert_der = build_self_signed_cert(wrong_key, "Attacker")

    result =
      https_get(@host, @tls_port, @path,
        verify: :verify_none,
        cert: wrong_cert_der,
        key: {:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, wrong_key)}
      )

    assert match?({:error, _}, result),
           "Expected TLS handshake to fail with wrong cert, got: #{inspect(result)}"
  end

  # Test 3: The correct client certificate (from /auth/mtls/get-client-cert).
  # The TLS handshake must succeed and the endpoint must return 200 with authenticated: true.
  test "correct client certificate returns 200 with authenticated true" do
    cert_pem = Leywn.MTLS.client_cert_pem()
    key_pem = Leywn.MTLS.client_key_pem()

    [{:Certificate, cert_der, _} | _] = :public_key.pem_decode(cert_pem)

    key_types = [:ECPrivateKey, :RSAPrivateKey, :PrivateKeyInfo, :DSAPrivateKey]

    {key_type, key_der, _} =
      Enum.find(:public_key.pem_decode(key_pem), fn {t, _, _} -> t in key_types end)

    {:ok, status, body} =
      https_get(@host, @tls_port, @path,
        verify: :verify_none,
        cert: cert_der,
        key: {key_type, key_der}
      )

    assert status == 200
    assert {:ok, decoded} = Jason.decode(body)
    assert decoded["authenticated"] == true
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Opens an SSL connection, sends a plain HTTP/1.0 GET, returns
  # {:ok, status_code, body} or {:error, reason}.
  defp https_get(host, port, path, ssl_opts) do
    connect_opts = ssl_opts ++ [active: false]

    case :ssl.connect(host, port, connect_opts, 5_000) do
      {:ok, sock} ->
        request = "GET #{path} HTTP/1.0\r\nHost: localhost\r\n\r\n"
        :ssl.send(sock, request)
        raw = recv_all(sock, <<>>)
        :ssl.close(sock)
        parse_http_response(raw)

      {:error, _} = err ->
        err
    end
  end

  defp recv_all(sock, acc) do
    case :ssl.recv(sock, 0, 2_000) do
      {:ok, data} -> recv_all(sock, acc <> IO.iodata_to_binary(data))
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end

  defp parse_http_response(raw) do
    case String.split(raw, "\r\n\r\n", parts: 2) do
      [header_block, body] ->
        [status_line | _] = String.split(header_block, "\r\n")
        [_http_ver, code | _] = String.split(status_line, " ")
        {:ok, String.to_integer(code), body}

      _ ->
        {:error, :bad_response}
    end
  end

  # Builds a minimal self-signed EC cert that is NOT issued by the Leywn CA.
  defp build_self_signed_cert(key, cn) do
    ecdsa_sha256 = {1, 2, 840, 10045, 4, 3, 2}
    id_ec_pk = {1, 2, 840, 10045, 2, 1}
    secp256r1 = {1, 2, 840, 10045, 3, 1, 7}
    id_at_cn = {2, 5, 4, 3}
    id_ce_bc = {2, 5, 29, 19}

    pub_bytes = ec_pub_bytes(key)

    spki =
      {:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, id_ec_pk, {:namedCurve, secp256r1}},
       {:ECPoint, pub_bytes}}

    subject = {:rdnSequence, [[{:AttributeTypeAndValue, id_at_cn, {:utf8String, cn}}]]}
    serial = :rand.uniform(1_000_000_000)

    tbs =
      {:OTPTBSCertificate, :v3, serial, {:SignatureAlgorithm, ecdsa_sha256, :asn1_NOVALUE},
       subject,
       {:Validity, {:generalTime, ~c"20240101000000Z"}, {:generalTime, ~c"20350101000000Z"}},
       subject, spki, :asn1_NOVALUE, :asn1_NOVALUE,
       [{:Extension, id_ce_bc, true, {:BasicConstraints, false, :asn1_NOVALUE}}]}

    :public_key.pkix_sign(tbs, key)
  end

  # OTP 26+ adds a 6th attributes field to ECPrivateKey
  defp ec_pub_bytes({:ECPrivateKey, _v, _priv, _params, pub, _attrs}), do: pub
  defp ec_pub_bytes({:ECPrivateKey, _v, _priv, _params, pub}), do: pub
end
