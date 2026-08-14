defmodule Leywn.Mock.RateLimit do
  @moduledoc """
  Fixed-window rate limiting for mutating mock requests.

  Two ceilings apply to every write. The per-IP budget stops a single caller
  from filling the overlay on its own; the global budget is what actually
  bounds the write rate, because an attacker with a thousand source addresses
  would otherwise have a thousand times the per-IP budget.

  Counters live in a public ETS table and are bumped with
  `:ets.update_counter/4`, which is atomic — no process sits in the path of a
  request. The window is encoded into the key rather than stored beside the
  count, so a new window starts by counting into a new key instead of by
  resetting an old one, and no read-modify-write race exists.

  The table is itself a memory surface — one row per source address — so the
  number of per-IP rows is capped. Past that cap new addresses are not tracked
  individually and only the global ceiling applies to them, which is the
  conservative direction: the limit that still holds is the stricter one.
  """

  use GenServer

  alias Leywn.Mock.Config

  @table :leywn_mock_ratelimit
  @window_seconds 60
  @sweep_interval_ms 60_000

  # An X-Forwarded-For value is caller-controlled, and it becomes part of an ETS
  # key. Truncating it bounds what one request can make this table hold.
  @max_client_key_bytes 64

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Charge one mutating request against both budgets.

  Returns `:ok`, or `{:error, :rate_limited, retry_after_seconds}`.
  """
  def check(conn) do
    now = System.os_time(:second)
    window = div(now, @window_seconds)
    retry_after = @window_seconds - rem(now, @window_seconds)

    with :ok <- charge_global(window, retry_after),
         :ok <- charge_client(conn, window, retry_after) do
      :ok
    end
  end

  @doc "Drop all counters. Exposed for tests."
  def reset, do: GenServer.call(__MODULE__, :reset)

  # ---------------------------------------------------------------------------
  # Counting
  # ---------------------------------------------------------------------------

  defp charge_global(window, retry_after) do
    limit = Config.global_write_rate_limit()

    if limit == 0 do
      {:error, :rate_limited, retry_after}
    else
      key = {:global, window}
      count = :ets.update_counter(@table, key, {2, 1}, {key, 0})
      if count > limit, do: {:error, :rate_limited, retry_after}, else: :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp charge_client(conn, window, retry_after) do
    limit = Config.write_rate_limit()

    if limit == 0 do
      {:error, :rate_limited, retry_after}
    else
      key = {:ip, client_key(conn), window}

      # A row that does not exist yet would grow the table. Once the cap is
      # reached, new addresses fall back to the global ceiling alone rather
      # than being allowed to expand this table without bound.
      if :ets.member(@table, key) or :ets.info(@table, :size) < Config.rate_limit_buckets() do
        count = :ets.update_counter(@table, key, {2, 1}, {key, 0})
        if count > limit, do: {:error, :rate_limited, retry_after}, else: :ok
      else
        :ok
      end
    end
  rescue
    ArgumentError -> :ok
  end

  @doc """
  The identity a write is charged to.

  Mirrors `LEYWN_TRUST_FORWARD`, so a Leywn behind a proxy limits the real
  caller rather than charging every request in the deployment to the proxy's
  own address.
  """
  def client_key(conn) do
    forwarded =
      if System.get_env("LEYWN_TRUST_FORWARD") == "true" do
        case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
          [header | _] -> header |> String.split(",") |> hd() |> String.trim()
          [] -> nil
        end
      end

    case forwarded do
      nil -> remote_ip_string(conn)
      "" -> remote_ip_string(conn)
      value -> binary_part(value, 0, min(byte_size(value), @max_client_key_bytes))
    end
  end

  defp remote_ip_string(conn) do
    case conn.remote_ip do
      nil ->
        "unknown"

      ip ->
        case :inet.ntoa(ip) do
          {:error, _} -> "unknown"
          charlist -> List.to_string(charlist)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    window = div(System.os_time(:second), @window_seconds)

    # Only the current window can still be counted into; everything older is
    # dead weight and is dropped wholesale.
    :ets.select_delete(@table, [
      {{{:global, :"$1"}, :_}, [{:<, :"$1", window}], [true]},
      {{{:ip, :_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
