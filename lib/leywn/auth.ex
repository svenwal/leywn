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

  def handle_mtls(conn) do
    case Plug.Conn.get_peer_data(conn) do
      %{ssl_cert: cert} when not is_nil(cert) ->
        cert_info = extract_cert_info(cert)
        {echo_data, conn} = build_echo(conn)

        Leywn.Respond.send(
          conn,
          200,
          Map.merge(echo_data, Map.merge(%{authenticated: true, auth_type: "mtls"}, cert_info)),
          root: "auth"
        )

      _ ->
        Leywn.Respond.send(
          conn,
          401,
          %{authenticated: false, error: "no client certificate presented"},
          root: "auth"
        )
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
