defmodule Leywn.Sleepers do
  @moduledoc """
  Bounds how many requests may be deliberately sleeping at once.

  `/delay` and the latency half of `/chaos-engineering` hold a connection for
  up to 30 seconds by design. Each listener accepts a limited number of
  connections, so without a ceiling a few hundred cheap requests would occupy
  all of them and starve every other endpoint. Capping the sleepers
  (`LEYWN_MAX_CONCURRENT_DELAYS`, default 250 of the 1 000 connections per
  listener) keeps capacity free for everything else; requests over the cap get
  a `503` with `Retry-After`.

  Slots are the pids of the sleeping request processes in a public ETS table.
  A request process that is killed instead of returning (Cowboy does this when
  a client disconnects) cannot run its cleanup, so a full table is purged of
  dead pids before a request is turned away.
  """

  use GenServer

  @table :leywn_sleepers
  @default_max 250

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The configured ceiling."
  def max_concurrent do
    with value when is_binary(value) <- System.get_env("LEYWN_MAX_CONCURRENT_DELAYS"),
         {n, ""} <- Integer.parse(String.trim(value)),
         true <- n >= 0 do
      n
    else
      _ -> @default_max
    end
  end

  @doc "Sleep for `ms` milliseconds, or return `:busy` if too many requests already are."
  def sleep(ms) when is_integer(ms) and ms >= 0 do
    if enter() do
      try do
        :timer.sleep(ms)
      after
        :ets.delete(@table, self())
      end
    else
      :busy
    end
  rescue
    # The table only goes away if this server is restarting; sleeping
    # unmetered for one request is better than failing it.
    ArgumentError -> :timer.sleep(ms)
  end

  defp enter do
    max = max_concurrent()
    :ets.insert(@table, {self()})

    cond do
      :ets.info(@table, :size) <= max ->
        true

      true ->
        purge_dead()

        if :ets.info(@table, :size) <= max do
          true
        else
          :ets.delete(@table, self())
          false
        end
    end
  end

  defp purge_dead do
    for {pid} <- :ets.tab2list(@table), not Process.alive?(pid), do: :ets.delete(@table, pid)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, write_concurrency: true])
    {:ok, %{}}
  end
end
