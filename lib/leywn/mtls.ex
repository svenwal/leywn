defmodule Leywn.MTLS do
  @moduledoc """
  Generates an in-memory CA, server certificate, and client certificate on every
  application start using OTP's built-in :public_key module.
  """

  # OIDs
  @ecdsa_with_sha256 {1, 2, 840, 10045, 4, 3, 2}
  @id_ec_public_key {1, 2, 840, 10045, 2, 1}
  @secp256r1 {1, 2, 840, 10045, 3, 1, 7}
  @id_at_common_name {2, 5, 4, 3}
  @id_ce_basic_constraints {2, 5, 29, 19}

  # Validity window: 2024-01-01 to 2035-01-01 (generalTime format)
  @not_before ~c"20240101000000Z"
  @not_after ~c"20350101000000Z"

  def init do
    ca_key = :public_key.generate_key({:namedCurve, :secp256r1})
    ca_cert_der = build_ca_cert(ca_key)

    {server_cert_der, server_key_opt} = load_or_generate_server_cert(ca_key, ca_cert_der)

    {extra_cacerts} = load_or_store_client_cert(ca_key, ca_cert_der)

    [
      cert: server_cert_der,
      key: server_key_opt,
      cacerts: [ca_cert_der | extra_cacerts],
      verify: :verify_peer,
      fail_if_no_peer_cert: false
    ]
  end

  defp load_or_generate_server_cert(ca_key, ca_cert_der) do
    key_pem = System.get_env("LEYWN_TLS_SERVER_KEY")
    cert_pem = System.get_env("LEYWN_TLS_SERVER_CRT")

    if key_pem && cert_pem do
      cert_der = validate_and_load_cert!(cert_pem)
      key_opt = parse_key_pem!(key_pem)
      {cert_der, key_opt}
    else
      server_key = :public_key.generate_key({:namedCurve, :secp256r1})
      server_cert_der = build_end_cert(server_key, "localhost", ca_key, ca_cert_der)
      {server_cert_der, {:ECPrivateKey, :public_key.der_encode(:ECPrivateKey, server_key)}}
    end
  end

  # Returns {extra_cacerts} — any certs from LEYWN_MTLS_CERT that the server must trust.
  defp load_or_store_client_cert(ca_key, ca_cert_der) do
    cert_pem = System.get_env("LEYWN_MTLS_CERT")
    key_pem  = System.get_env("LEYWN_MTLS_KEY")

    if cert_pem && key_pem do
      cert_ders = parse_cert_ders!(cert_pem, "LEYWN_MTLS_CERT")
      _key_opt  = parse_key_pem!(key_pem)   # validates the key PEM

      :persistent_term.put(:leywn_mtls, %{
        client_cert_pem: cert_pem,
        client_key_pem: key_pem
      })

      # Trust all certs from the provided PEM (leaf + any chain/CA certs) so that
      # verify: :verify_peer accepts this client certificate during the TLS handshake.
      {cert_ders}
    else
      client_key = :public_key.generate_key({:namedCurve, :secp256r1})
      client_cert_der = build_end_cert(client_key, "Leywn Demo Client", ca_key, ca_cert_der)

      :persistent_term.put(:leywn_mtls, %{
        client_cert_pem: cert_to_pem(client_cert_der),
        client_key_pem: key_to_pem(client_key)
      })

      {[]}
    end
  end

  defp parse_cert_ders!(pem_string, env_var) do
    ders = for {:Certificate, der, _} <- :public_key.pem_decode(pem_string), do: der

    if ders == [] do
      IO.puts("ERROR: #{env_var} does not contain a valid PEM certificate — aborting")
      System.halt(1)
    end

    ders
  end

  defp validate_and_load_cert!(pem_string) do
    entries = :public_key.pem_decode(pem_string)

    cert_entry = Enum.find(entries, fn {type, _, _} -> type == :Certificate end)

    if cert_entry == nil do
      IO.puts("ERROR: LEYWN_TLS_SERVER_CRT does not contain a valid PEM certificate — aborting")
      System.halt(1)
    end

    {:Certificate, der, _} = cert_entry

    cert =
      try do
        :public_key.pkix_decode_cert(der, :otp)
      rescue
        _ ->
          IO.puts("ERROR: LEYWN_TLS_SERVER_CRT contains an invalid certificate — aborting")
          System.halt(1)
      end

    check_cert_expiry(cert)
    der
  end

  defp check_cert_expiry(cert) do
    {:'OTPCertificate', tbs, _, _} = cert
    {:'OTPTBSCertificate', _, _, _, _, validity, _, _, _, _, _} = tbs
    {:'Validity', _not_before, not_after} = validity

    cert_secs = not_after |> asn1_time_to_datetime() |> :calendar.datetime_to_gregorian_seconds()
    now_secs = :calendar.universal_time() |> :calendar.datetime_to_gregorian_seconds()

    if cert_secs < now_secs do
      IO.puts("WARNING: LEYWN_TLS_SERVER_CRT certificate has expired but will still be used")
    end
  end

  defp asn1_time_to_datetime({:utcTime, t}) do
    t = to_string(t)
    <<y2::binary-2, mo::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2, _::binary>> = t
    year = String.to_integer(y2)
    year = if year >= 50, do: 1900 + year, else: 2000 + year
    {{year, String.to_integer(mo), String.to_integer(d)},
     {String.to_integer(h), String.to_integer(mi), String.to_integer(s)}}
  end

  defp asn1_time_to_datetime({:generalTime, t}) do
    t = to_string(t)
    <<year::binary-4, mo::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2, _::binary>> = t
    {{String.to_integer(year), String.to_integer(mo), String.to_integer(d)},
     {String.to_integer(h), String.to_integer(mi), String.to_integer(s)}}
  end

  defp parse_key_pem!(pem_string) do
    entries = :public_key.pem_decode(pem_string)

    key_types = [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo, :"DSAPrivateKey"]
    key_entry = Enum.find(entries, fn {type, _, _} -> type in key_types end)

    if key_entry == nil do
      IO.puts("ERROR: LEYWN_TLS_SERVER_KEY does not contain a valid PEM private key — aborting")
      System.halt(1)
    end

    {type, der, _} = key_entry
    {type, der}
  end

  def client_cert_pem, do: :persistent_term.get(:leywn_mtls).client_cert_pem
  def client_key_pem, do: :persistent_term.get(:leywn_mtls).client_key_pem

  defp build_ca_cert(key) do
    subject = rdn("Leywn Demo CA")
    serial = :rand.uniform(1_000_000_000)
    extensions = [basic_constraints_ext(true)]
    tbs = otp_tbs(serial, subject, subject, ec_spki(key), extensions)
    :public_key.pkix_sign(tbs, key)
  end

  defp build_end_cert(key, cn, ca_key, ca_cert_der) do
    ca_cert = :public_key.pkix_decode_cert(ca_cert_der, :otp)
    ca_subject = cert_subject(ca_cert)
    subject = rdn(cn)
    serial = :rand.uniform(1_000_000_000)
    extensions = [basic_constraints_ext(false)]
    tbs = otp_tbs(serial, ca_subject, subject, ec_spki(key), extensions)
    :public_key.pkix_sign(tbs, ca_key)
  end

  defp otp_tbs(serial, issuer, subject, spki, extensions) do
    {:'OTPTBSCertificate',
     :v3,
     serial,
     {:'SignatureAlgorithm', @ecdsa_with_sha256, :asn1_NOVALUE},
     issuer,
     {:'Validity', {:generalTime, @not_before}, {:generalTime, @not_after}},
     subject,
     spki,
     :asn1_NOVALUE,
     :asn1_NOVALUE,
     extensions}
  end

  defp ec_spki({:'ECPrivateKey', _version, _priv, _params, pub_bytes}) do
    {:'OTPSubjectPublicKeyInfo',
     {:'PublicKeyAlgorithm', @id_ec_public_key, {:namedCurve, @secp256r1}},
     {:ECPoint, pub_bytes}}
  end

  # OTP 26+ adds a 6th attributes field to ECPrivateKey
  defp ec_spki({:'ECPrivateKey', _version, _priv, _params, pub_bytes, _attrs}) do
    {:'OTPSubjectPublicKeyInfo',
     {:'PublicKeyAlgorithm', @id_ec_public_key, {:namedCurve, @secp256r1}},
     {:ECPoint, pub_bytes}}
  end

  defp rdn(cn) do
    {:rdnSequence, [[{:'AttributeTypeAndValue', @id_at_common_name, {:utf8String, cn}}]]}
  end

  defp basic_constraints_ext(is_ca) do
    {:'Extension', @id_ce_basic_constraints, true, {:'BasicConstraints', is_ca, :asn1_NOVALUE}}
  end

  defp cert_subject({:'OTPCertificate', tbs, _, _}) do
    {:'OTPTBSCertificate', _, _, _, _issuer, _, subject, _, _, _, _} = tbs
    subject
  end

  defp cert_to_pem(der) do
    :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
  end

  defp key_to_pem(key) do
    :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, key)])
  end
end
