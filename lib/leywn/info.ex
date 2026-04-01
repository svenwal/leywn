defmodule Leywn.Info do
  import Bitwise

  def ip_data(conn) do
    {v4, v6} = resolve_ip(conn)
    %{ipv4: v4, ipv6: v6}
  end

  def ipv4_data(conn) do
    {v4, _} = resolve_ip(conn)
    %{ipv4: v4}
  end

  def ipv6_data(conn) do
    {_, v6} = resolve_ip(conn)
    %{ipv6: v6}
  end

  defp resolve_ip(conn) do
    if System.get_env("LEYWN_TRUST_FORWARD") == "true" do
      case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
        [header | _] ->
          header
          |> String.split(",")
          |> hd()
          |> String.trim()
          |> classify_ip_string()

        [] ->
          classify_ip(conn.remote_ip)
      end
    else
      classify_ip(conn.remote_ip)
    end
  end

  defp classify_ip_string(ip_str) do
    cond do
      String.contains?(ip_str, ":") -> {nil, ip_str}
      String.contains?(ip_str, ".") -> {ip_str, nil}
      true -> {nil, nil}
    end
  end

  def date_utc do
    dt = DateTime.utc_now()
    %{date: Date.to_iso8601(DateTime.to_date(dt)), timezone: "UTC"}
  end

  def date_tz(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> {:ok, %{date: Date.to_iso8601(DateTime.to_date(dt)), timezone: timezone}}
      _ -> {:error, :not_found}
    end
  end

  def time_utc do
    dt = DateTime.utc_now()
    %{time: DateTime.to_iso8601(dt), timezone: "UTC"}
  end

  def time_tz(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> {:ok, %{time: DateTime.to_iso8601(dt), timezone: timezone}}
      _ -> {:error, :not_found}
    end
  end

  defp classify_ip({a, b, c, d}) do
    {"#{a}.#{b}.#{c}.#{d}", nil}
  end

  defp classify_ip({0, 0, 0, 0, 0, 0xFFFF, hi, lo}) do
    a = hi >>> 8
    b = hi &&& 0xFF
    c = lo >>> 8
    d = lo &&& 0xFF
    {"#{a}.#{b}.#{c}.#{d}", format_ipv6({0, 0, 0, 0, 0, 0xFFFF, hi, lo})}
  end

  defp classify_ip({_, _, _, _, _, _, _, _} = ip) do
    {nil, format_ipv6(ip)}
  end

  defp classify_ip(_), do: {nil, nil}

  defp format_ipv6({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
    |> String.downcase()
  end
end
