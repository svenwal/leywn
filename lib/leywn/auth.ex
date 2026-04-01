defmodule Leywn.Auth do
  import Plug.Conn

  def handle_basic(conn, expected_user, expected_pass) do
    case check_basic(conn, expected_user, expected_pass) do
      {:ok, auth_data} ->
        {echo_data, conn} = build_echo(conn)
        Leywn.Respond.send(conn, 200, Map.merge(echo_data, auth_data), root: "auth")

      {:error, _} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="Leywn"))
        |> Leywn.Respond.send(401, %{authenticated: false, error: "unauthorized"}, root: "auth")
    end
  end

  def handle_api_key(conn, header_name, key_value) do
    case check_api_key(conn, header_name, key_value) do
      {:ok, auth_data} ->
        {echo_data, conn} = build_echo(conn)
        Leywn.Respond.send(conn, 200, Map.merge(echo_data, auth_data), root: "auth")

      {:error, _} ->
        Leywn.Respond.send(conn, 401, %{authenticated: false, error: "unauthorized"}, root: "auth")
    end
  end

  def handle_jwt(conn) do
    case check_jwt(conn) do
      {:ok, auth_data} ->
        {echo_data, conn} = build_echo(conn)
        Leywn.Respond.send(conn, 200, Map.merge(echo_data, auth_data), root: "auth")

      {:error, _} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="Leywn"))
        |> Leywn.Respond.send(401, %{authenticated: false, error: "unauthorized"}, root: "auth")
    end
  end

  defp check_basic(conn, expected_user, expected_pass) do
    with [auth | _] <- get_req_header(conn, "authorization"),
         [scheme, encoded] <- String.split(auth, " ", parts: 2),
         true <- String.downcase(scheme) == "basic",
         {:ok, credentials} <- Base.decode64(String.trim(encoded)),
         [user, pass] <- String.split(credentials, ":", parts: 2),
         true <- user == expected_user and pass == expected_pass do
      {:ok, %{authenticated: true, auth_type: "basic-auth", username: expected_user}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp check_api_key(conn, header_name, key_value) do
    case get_req_header(conn, String.downcase(header_name)) do
      [^key_value | _] ->
        {:ok, %{authenticated: true, auth_type: "api-key", header: header_name}}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp check_jwt(conn) do
    with [auth | _] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- auth,
         [header_b64, payload_b64, _sig] <- String.split(token, "."),
         {:ok, header_json} <- base64url_decode(header_b64),
         {:ok, payload_json} <- base64url_decode(payload_b64),
         {:ok, jwt_header} <- Jason.decode(header_json),
         {:ok, claims} <- Jason.decode(payload_json) do
      {:ok, %{authenticated: true, auth_type: "jwt", jwt_header: jwt_header, claims: claims}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def handle_jwt_exchange(conn) do
    case check_jwt(conn) do
      {:ok, %{claims: incoming_claims}} ->
        key = Application.get_env(:leywn, :jwt_signing_key)
        now = System.system_time(:second)

        header = %{"alg" => "HS256", "typ" => "JWT"}

        new_claims =
          Map.merge(incoming_claims, %{
            "iss" => "leywn",
            "iat" => now,
            "jti" => Leywn.Random.uuid()
          })

        header_b64 = Base.url_encode64(Jason.encode!(header), padding: false)
        payload_b64 = Base.url_encode64(Jason.encode!(new_claims), padding: false)
        signing_input = header_b64 <> "." <> payload_b64
        sig = :crypto.mac(:hmac, :sha256, key, signing_input)
        token = signing_input <> "." <> Base.url_encode64(sig, padding: false)

        {echo_data, conn} = build_echo(conn)

        Leywn.Respond.send(
          conn,
          200,
          Map.merge(echo_data, %{
            authenticated: true,
            auth_type: "jwt",
            exchanged_token: token,
            claims: new_claims
          }),
          root: "auth"
        )

      {:error, _} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="Leywn"))
        |> Leywn.Respond.send(401, %{authenticated: false, error: "unauthorized"}, root: "auth")
    end
  end

  def handle_mtls(conn) do
    case get_mtls_cert(conn) do
      {:ok, cert_der} ->
        cert_info = extract_cert_info(cert_der)
        {echo_data, conn} = build_echo(conn)

        Leywn.Respond.send(
          conn,
          200,
          Map.merge(echo_data, Map.merge(%{authenticated: true, auth_type: "mtls"}, cert_info)),
          root: "auth"
        )

      {:error, reason} ->
        Leywn.Respond.send(conn, 401, %{authenticated: false, error: reason}, root: "auth")
    end
  end

  defp get_mtls_cert(conn) do
    case System.get_env("LEYWN_MTLS_IN_HEADER") do
      nil ->
        case Plug.Conn.get_peer_data(conn) do
          %{ssl_cert: cert} when not is_nil(cert) -> {:ok, cert}
          _ -> {:error, "no client certificate presented"}
        end

      header_name ->
        case get_req_header(conn, String.downcase(header_name)) do
          [] ->
            {:error, "missing certificate header #{header_name}"}

          [pem | _] ->
            pem
            |> URI.decode()
            |> :public_key.pem_decode()
            |> case do
              [{:Certificate, der, :not_encrypted} | _] -> {:ok, der}
              _ -> {:error, "invalid PEM certificate in header #{header_name}"}
            end
        end
    end
  end

  defp base64url_decode(str) do
    stripped = String.trim_trailing(str, "=")
    padding = rem(4 - rem(String.length(stripped), 4), 4)
    Base.url_decode64(stripped <> String.duplicate("=", padding))
  end

  defp build_echo(conn) do
    conn = Plug.Conn.fetch_query_params(conn)
    max_body = Application.get_env(:leywn, :echo_max_body_bytes, 65_536)
    {body_info, conn} = Leywn.Body.read(conn, max_body)
    {Leywn.Echo.build(conn, body_info), conn}
  end

  defp extract_cert_info(der) do
    try do
      {:'OTPCertificate', tbs, _, _} = :public_key.pkix_decode_cert(der, :otp)
      {:'OTPTBSCertificate', _, _, _, issuer, _, subject, _, _, _, _} = tbs
      %{client_dn: format_rdn(subject), client_ca: format_rdn(issuer)}
    rescue
      _ -> %{}
    end
  end

  defp format_rdn({:rdnSequence, rdns}) do
    rdns
    |> Enum.flat_map(fn attrs ->
      Enum.map(attrs, fn {:'AttributeTypeAndValue', oid, value} ->
        "#{oid_name(oid)}=#{rdn_value(value)}"
      end)
    end)
    |> Enum.join(", ")
  end

  defp rdn_value({:utf8String, v}), do: v
  defp rdn_value({:printableString, v}), do: List.to_string(v)
  defp rdn_value(v) when is_list(v), do: List.to_string(v)
  defp rdn_value(v) when is_binary(v), do: v
  defp rdn_value(v), do: inspect(v)

  defp oid_name({2, 5, 4, 3}), do: "CN"
  defp oid_name({2, 5, 4, 6}), do: "C"
  defp oid_name({2, 5, 4, 7}), do: "L"
  defp oid_name({2, 5, 4, 8}), do: "ST"
  defp oid_name({2, 5, 4, 10}), do: "O"
  defp oid_name({2, 5, 4, 11}), do: "OU"
  defp oid_name(oid), do: inspect(oid)
end
