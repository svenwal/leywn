defmodule Leywn.Codec do
  @moduledoc """
  POST body encode / decode operations.
  Each function returns {:ok, content_type, body} or {:error, message}.
  """

  def base64_encode(body),
    do: {:ok, "text/plain", Base.encode64(body)}

  def base64_decode(body) do
    case Base.decode64(String.trim(body), ignore: :whitespace) do
      {:ok, decoded} -> {:ok, "text/plain", decoded}
      :error -> {:error, "invalid Base64 input"}
    end
  end

  def url_encode(body),
    do: {:ok, "text/plain", URI.encode(body)}

  def url_decode(body) do
    try do
      {:ok, "text/plain", URI.decode(body)}
    rescue
      _ -> {:error, "invalid URL-encoded input"}
    end
  end

  def rot13(body) do
    result =
      body
      |> :binary.bin_to_list()
      |> Enum.map(fn
        c when c in ?a..?z -> rem(c - ?a + 13, 26) + ?a
        c when c in ?A..?Z -> rem(c - ?A + 13, 26) + ?A
        c -> c
      end)
      |> :binary.list_to_bin()

    {:ok, "text/plain", result}
  end

  def jwt_decode(body) do
    token = String.trim(body)

    case String.split(token, ".") do
      [header_b64, payload_b64 | _] ->
        with {:ok, hdr_json} <- b64url_decode(header_b64),
             {:ok, pay_json} <- b64url_decode(payload_b64),
             {:ok, header} <- Jason.decode(hdr_json),
             {:ok, payload} <- Jason.decode(pay_json) do
          out = Jason.encode!(%{"header" => header, "payload" => payload}, pretty: true)
          {:ok, "application/json", out}
        else
          _ -> {:error, "invalid JWT format"}
        end

      _ ->
        {:error, "invalid JWT format"}
    end
  end

  def hex_encode(body),
    do: {:ok, "text/plain", Base.encode16(body, case: :lower)}

  def hex_decode(body) do
    input = body |> String.trim() |> String.upcase()
    case Base.decode16(input) do
      {:ok, decoded} -> {:ok, "text/plain", decoded}
      :error -> {:error, "invalid hex input"}
    end
  end

  defp b64url_decode(str) do
    stripped = String.trim_trailing(str, "=")
    padding = rem(4 - rem(String.length(stripped), 4), 4)
    Base.url_decode64(stripped <> String.duplicate("=", padding))
  end
end
