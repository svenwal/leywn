defmodule Leywn.Chaos do
  import Plug.Conn

  @default_error_pct 10
  @default_mangled_pct 10
  @default_latency_pct 20
  @default_max_latency 2000

  # HTTP status codes that make sense as injected errors
  @error_codes [400, 401, 403, 404, 408, 409, 422, 429, 500, 502, 503, 504]

  def defaults do
    %{
      error_pct: @default_error_pct,
      mangled_pct: @default_mangled_pct,
      latency_pct: @default_latency_pct,
      max_latency: @default_max_latency
    }
  end

  @doc "Parse and validate path params; returns {:ok, params} or {:error, reason}."
  def from_path(ep, mp, lp, ml) do
    with {error_pct, ""} <- Integer.parse(ep),
         {mangled_pct, ""} <- Integer.parse(mp),
         {latency_pct, ""} <- Integer.parse(lp),
         {max_latency, ""} <- Integer.parse(ml),
         :ok <- validate_pct(error_pct, "error_percentage"),
         :ok <- validate_pct(mangled_pct, "mangled_percentage"),
         :ok <- validate_pct(latency_pct, "latency_percentage"),
         :ok <- validate_latency(max_latency) do
      {:ok,
       %{
         error_pct: error_pct,
         mangled_pct: mangled_pct,
         latency_pct: latency_pct,
         max_latency: max_latency
       }}
    else
      {:error, field, msg} -> {:error, field, msg}
      _ -> {:error, "params", "invalid integer"}
    end
  end

  @doc "Read chaos params from X-Chaos-* request headers, falling back to defaults."
  def from_headers(conn) do
    %{
      error_pct: header_int(conn, "x-chaos-error-percentage", @default_error_pct),
      mangled_pct: header_int(conn, "x-chaos-mangled-percentage", @default_mangled_pct),
      latency_pct: header_int(conn, "x-chaos-latency-percentage", @default_latency_pct),
      max_latency: header_int(conn, "x-chaos-maximum-latency", @default_max_latency)
    }
  end

  @doc "Apply chaos to a connection, using the echo_data map as the happy-path body."
  def apply_chaos(conn, params, echo_data) do
    latency_ms = maybe_latency(params)
    if latency_ms > 0, do: :timer.sleep(latency_ms)

    chaos_meta = %{
      error_percentage: params.error_pct,
      mangled_percentage: params.mangled_pct,
      latency_percentage: params.latency_pct,
      maximum_latency_ms: params.max_latency,
      latency_applied_ms: latency_ms
    }

    cond do
      roll?(params.error_pct) ->
        status = Enum.random(@error_codes)

        Leywn.Respond.send(
          conn,
          status,
          %{
            error: "chaos_error_injected",
            _chaos:
              Map.merge(chaos_meta, %{error_injected: true, mangled: false, status_code: status})
          },
          root: "chaos"
        )

      roll?(params.mangled_pct) ->
        full =
          Jason.encode!(
            Map.put(
              echo_data,
              :_chaos,
              Map.merge(chaos_meta, %{error_injected: false, mangled: true})
            )
          )

        # Truncate mid-stream so the JSON is syntactically invalid
        mangled = String.slice(full, 0, max(1, div(byte_size(full), 2))) <> "!!MANGLED"

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, mangled)

      true ->
        Leywn.Respond.send(
          conn,
          200,
          Map.put(
            echo_data,
            :_chaos,
            Map.merge(chaos_meta, %{error_injected: false, mangled: false})
          ),
          root: "chaos"
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp maybe_latency(%{latency_pct: pct, max_latency: max}) do
    if roll?(pct) and max > 0, do: :rand.uniform(max), else: 0
  end

  # Returns true with probability pct/100. pct=0 → never, pct=100 → always.
  defp roll?(0), do: false
  defp roll?(100), do: true
  defp roll?(pct), do: :rand.uniform(100) <= pct

  defp validate_pct(n, _field) when n >= 0 and n <= 100, do: :ok
  defp validate_pct(_, field), do: {:error, field, "must be 0–100"}

  defp validate_latency(n) when n >= 0 and n <= 30_000, do: :ok
  defp validate_latency(_), do: {:error, "maximum_latency", "must be 0–30000"}

  defp header_int(conn, name, default) do
    case get_req_header(conn, name) do
      [val | _] ->
        case Integer.parse(val) do
          {n, ""} -> n
          _ -> default
        end

      [] ->
        default
    end
  end
end
