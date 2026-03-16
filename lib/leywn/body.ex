defmodule Leywn.Body do
  @default_read_length 8_000

  def read(conn, max_bytes) when is_integer(max_bytes) and max_bytes >= 0 do
    opts = [length: max_bytes, read_length: min(@default_read_length, max(max_bytes, 1))]

    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {body_info(body, truncated: false), conn}

      {:more, partial, conn} ->
        {body_info(partial, truncated: true), conn}

      {:error, reason} ->
        {%{present: false, bytes: 0, truncated: false, included: false, reason: inspect(reason)}, conn}
    end
  end

  defp body_info(body, truncated: truncated?) do
    bytes = byte_size(body)
    present? = bytes > 0
    utf8? = present? and String.valid?(body)

    included? = utf8?

    %{
      present: present?,
      bytes: bytes,
      truncated: truncated?,
      utf8: utf8?,
      included: included?,
      body: if(included?, do: body, else: nil),
      reason:
        cond do
          not present? -> nil
          not utf8? -> "binary_or_invalid_utf8"
          truncated? -> "truncated"
          true -> nil
        end
    }
  end
end

