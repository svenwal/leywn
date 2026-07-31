defmodule Leywn.Echo do
  def build(conn, body_info) when is_map(body_info) do
    %{
      method: conn.method,
      scheme: to_string(conn.scheme),
      host: conn.host,
      port: conn.port,
      path: conn.request_path,
      path_info: conn.path_info,
      query_string: conn.query_string,
      query_params: conn.query_params,
      headers: headers_map(conn.req_headers),
      remote_ip: ip_to_string(conn.remote_ip),
      body: body_info,
      timestamp_unix_ms: System.system_time(:millisecond)
    }
  end

  # A header sent once is reported as a plain string; only genuinely repeated
  # headers become a list. Wrapping every value in a single-element array forces
  # consumers to unwrap the common case for no reason.
  defp headers_map(headers) do
    headers
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Map.new(fn
      {k, [single]} -> {k, single}
      {k, many} -> {k, many}
    end)
  end

  defp ip_to_string(nil), do: nil

  defp ip_to_string({a, b, c, d}) do
    Enum.join([a, b, c, d], ".")
  end

  defp ip_to_string({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp ip_to_string(other), do: inspect(other)
end
