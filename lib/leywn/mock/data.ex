defmodule Leywn.Mock.Data do
  @moduledoc """
  The read model: file data with the write overlay applied.

  `Leywn.Mock.Loader` holds records exactly as the JSON file declared them and
  never changes them; `Leywn.Mock.Store` holds what callers have written since
  startup. Neither is the answer to a request on its own — this module is where
  the two are combined, so that a record updated through `PATCH` reads back
  changed, a deleted one disappears, and a created one appears at the end of
  its collection.

  Because the overlay expires, the same read a few minutes later returns the
  file data again. That is the intended behaviour, not drift.
  """

  alias Leywn.Mock.{Inflect, Loader, Store}

  @doc """
  All records of a collection, in file order, with created records appended in
  the order they were written.
  """
  def list(mock, collection) do
    case Map.fetch(mock.collections, collection) do
      {:ok, base} -> merge(mock.name, collection, base)
      :error -> nil
    end
  end

  @doc "A single record by id, or `:error` when it does not exist or was deleted."
  def get(mock, collection, id_key) do
    case Map.fetch(mock.collections, collection) do
      {:ok, base} ->
        case Store.get(mock.name, collection, id_key) do
          {:ok, record} -> {:ok, record}
          :deleted -> :error
          :miss -> Map.fetch(base.index, id_key)
        end

      :error ->
        :error
    end
  end

  @doc "True when the collection exists in the file data."
  def collection?(mock, name), do: Map.has_key?(mock.collections, name)

  @doc "True when the name refers to a single-object resource rather than a collection."
  def singleton?(mock, name), do: Map.has_key?(mock.singletons, name)

  @doc """
  An id for a newly created record.

  The shape follows the ids already in the file so a generated id is not
  obviously foreign next to them: integer ids continue the sequence, anything
  else gets a random hex string. `taken?` guards against colliding with an id
  that only exists in the overlay.
  """
  def next_id(mock, collection, taken?) do
    base = Map.fetch!(mock.collections, collection)

    case base.id_type do
      :integer -> next_free_integer(base.max_int_id + 1, taken?)
      _ -> next_free_string(taken?, 0)
    end
  end

  defp next_free_integer(candidate, taken?) do
    if taken?.(Loader.id_key(candidate)),
      do: next_free_integer(candidate + 1, taken?),
      else: candidate
  end

  # Bounded rather than a `while true`: 8 random hex characters collide with a
  # handful of overlay entries only through a fault, and an unbounded retry
  # inside a request is a worse failure than a long id.
  defp next_free_string(taken?, attempt) when attempt < 8 do
    candidate = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    if taken?.(candidate), do: next_free_string(taken?, attempt + 1), else: candidate
  end

  defp next_free_string(_taken?, _attempt) do
    8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  @doc """
  Records of `child` related to `id` in `parent`.

  Mirrors json-server's convention: `/users/{id}/orders` returns the orders
  whose `userId` matches. The foreign key is discovered from the child records
  rather than assumed, so a dataset spelling it `user_id` works too. Returns
  `nil` when no such key exists, which the caller reports as a 404 rather than
  as an empty list — an empty list would suggest the relation exists and simply
  has no members.
  """
  def related(mock, parent, id_key, child) do
    with records when is_list(records) <- list(mock, child),
         key when is_binary(key) <- relation_key(records, parent) do
      Enum.filter(records, fn record ->
        Loader.id_key(Map.get(record, key)) == id_key
      end)
    else
      _ -> nil
    end
  end

  @doc """
  The field in `records` that points back at `parent`, or `nil`.

  Also used when generating a mock's OpenAPI, so that the nested routes the
  spec advertises are exactly the ones the handler can actually serve.
  """
  def relation_key(records, parent) do
    sample = Enum.take(records, 20)

    parent
    |> Inflect.foreign_keys()
    |> Enum.find(fn key -> Enum.any?(sample, &Map.has_key?(&1, key)) end)
  end

  # ---------------------------------------------------------------------------
  # Merging
  # ---------------------------------------------------------------------------

  defp merge(mock_name, collection, base) do
    entries = Store.overlay(mock_name, collection)

    if entries == [] do
      base.records
    else
      ops = Map.new(entries, fn {id, op, record, _seq} -> {id, {op, record}} end)

      kept =
        Enum.flat_map(base.records, fn record ->
          case record_id(record) do
            nil ->
              [record]

            id ->
              case Map.get(ops, id) do
                nil -> [record]
                {:delete, _} -> []
                {:put, updated} -> [updated]
              end
          end
        end)

      created =
        entries
        |> Enum.filter(fn {id, op, _record, _seq} ->
          op == :put and not Map.has_key?(base.index, id)
        end)
        |> Enum.map(fn {_id, _op, record, _seq} -> record end)

      kept ++ created
    end
  end

  defp record_id(record) do
    case Map.fetch(record, "id") do
      {:ok, id} -> Loader.id_key(id)
      :error -> nil
    end
  end
end
