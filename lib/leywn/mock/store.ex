defmodule Leywn.Mock.Store do
  @moduledoc """
  Holds the mutable overlay that mock writes produce.

  The datasets themselves are immutable — `Leywn.Mock.Loader` publishes them
  once and never touches them again. Everything a caller writes lands here
  instead, as a thin layer of creates, updates and delete markers that reads
  merge on top of the file data.

  Three properties make that layer safe to expose:

    * every entry carries an expiry, so state is a lease rather than a store
      and anything written is reclaimed without operator involvement;
    * entries are capped per mock, so one mock cannot crowd out another;
    * total bytes are capped across all mocks, because an entry count on its
      own says nothing about memory — a hundred 16 KiB entries per mock is
      megabytes once several mocks are mounted.

  Reads go straight to ETS from the request process. Writes go through this
  process so that the caps and the counters are evaluated and applied together;
  at the global write rate limit that serialisation is nowhere near a
  bottleneck.
  """

  use GenServer

  alias Leywn.Mock.Config

  @table :leywn_mock_overlay

  # How often expired entries are reclaimed. Reads discard expired entries on
  # sight regardless, so this interval governs when the memory comes back, not
  # when the data stops being visible.
  @sweep_interval_ms 10_000

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Every live overlay entry for a collection.

  Returns a list of `{id_key, op, record, seq}` where `op` is `:put` or
  `:delete`, ordered by insertion so created records appear in the order they
  were written.
  """
  def overlay(mock, collection) when is_binary(mock) and is_binary(collection) do
    now = now_ms()

    @table
    |> :ets.select([
      {{{mock, collection, :"$1"}, :"$2", :"$3", :"$4", :"$5", :_}, [{:>, :"$4", now}],
       [{{:"$1", :"$2", :"$3", :"$5"}}]}
    ])
    |> Enum.sort_by(fn {_id, _op, _record, seq} -> seq end)
  rescue
    ArgumentError -> []
  end

  @doc """
  Look up a single overlay entry.

  Returns `{:ok, record}` for a create or update, `:deleted` when the id has
  been deleted, or `:miss` when the overlay has nothing to say about it and the
  underlying file data stands.
  """
  def get(mock, collection, id_key) do
    case :ets.lookup(@table, {mock, collection, id_key}) do
      [{_key, op, record, expires_at, _seq, _bytes}] ->
        if expires_at > now_ms() do
          case op do
            :put -> {:ok, record}
            :delete -> :deleted
          end
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc """
  Record a created or updated record.

  Returns `:ok`, or `{:error, :too_many_entries}` / `{:error, :overlay_full}`
  when a cap would be exceeded.
  """
  def put(mock, collection, id_key, record) do
    GenServer.call(__MODULE__, {:put, mock, collection, id_key, record, :put})
  end

  @doc "Record a delete marker for an id. Subject to the same caps as a write."
  def delete(mock, collection, id_key) do
    GenServer.call(__MODULE__, {:put, mock, collection, id_key, nil, :delete})
  end

  @doc "Live overlay entry count for one mock."
  def count(mock), do: GenServer.call(__MODULE__, {:count, mock})

  @doc "Live overlay statistics across all mocks."
  def stats, do: GenServer.call(__MODULE__, :stats)

  @doc "Drop all overlay state. Exposed for tests."
  def reset, do: GenServer.call(__MODULE__, :reset)

  # ---------------------------------------------------------------------------
  # Server
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # read_concurrency: reads outnumber writes by a wide margin here, and every
    # read happens in its own request process.
    :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    schedule_sweep()
    {:ok, %{seq: 0, counts: %{}, bytes: 0}}
  end

  @impl true
  def handle_call({:put, mock, collection, id_key, record, op}, _from, state) do
    key = {mock, collection, id_key}
    size = entry_bytes(record)
    existing = :ets.lookup(@table, key)

    {replacing?, freed_bytes} =
      case existing do
        [{_key, _op, _rec, expires_at, _seq, bytes}] -> {expires_at > now_ms(), bytes}
        [] -> {false, 0}
      end

    # An expired row still occupying the table is reclaimed here rather than
    # counted against the caller; the sweeper would have taken it shortly.
    state =
      if existing != [] and not replacing?, do: release(state, mock, freed_bytes), else: state

    current_count = Map.get(state.counts, mock, 0)
    projected_count = if replacing?, do: current_count, else: current_count + 1
    projected_bytes = state.bytes - if(replacing?, do: freed_bytes, else: 0) + size

    cond do
      projected_count > Config.max_new_entries() ->
        {:reply, {:error, :too_many_entries}, state}

      projected_bytes > Config.max_overlay_bytes() ->
        {:reply, {:error, :overlay_full}, state}

      true ->
        seq = state.seq + 1
        expires_at = now_ms() + Config.entry_ttl_seconds() * 1000
        :ets.insert(@table, {key, op, record, expires_at, seq, size})

        {:reply, :ok,
         %{
           state
           | seq: seq,
             counts: Map.put(state.counts, mock, projected_count),
             bytes: projected_bytes
         }}
    end
  end

  def handle_call({:count, mock}, _from, state) do
    {:reply, Map.get(state.counts, mock, 0), state}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{entries: Enum.sum(Map.values(state.counts)), bytes: state.bytes}, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, %{state | counts: %{}, bytes: 0}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = now_ms()

    expired =
      :ets.select(@table, [
        {{{:"$1", :"$2", :"$3"}, :_, :_, :"$4", :_, :"$5"}, [{:"=<", :"$4", now}],
         [{{:"$1", :"$2", :"$3", :"$5"}}]}
      ])

    state =
      Enum.reduce(expired, state, fn {mock, collection, id, bytes}, acc ->
        :ets.delete(@table, {mock, collection, id})
        release(acc, mock, bytes)
      end)

    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp release(state, mock, bytes) do
    %{
      state
      | counts: Map.update(state.counts, mock, 0, &max(&1 - 1, 0)),
        bytes: max(state.bytes - bytes, 0)
    }
  end

  # external_size is the term's serialised footprint — a far better proxy for
  # what it costs to hold than the length of the request that produced it.
  defp entry_bytes(nil), do: 0
  defp entry_bytes(record), do: :erlang.external_size(record)

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
