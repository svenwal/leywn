defmodule Leywn.Mock.Loader do
  @moduledoc """
  Reads the mocks directory once at startup and publishes the result to
  `:persistent_term`.

  Datasets are read exactly once. Re-reading and re-parsing a JSON file on every
  request would make a mock with a large file an amplification target — one
  cheap HTTP request costing megabytes of parsing — and `:persistent_term`
  additionally lets every request read the data without copying it into the
  request process.

  The trade-off is that replacing a mounted file requires a restart, which
  matches how `priv/names.txt` and `priv/email_domains.txt` already behave.
  """

  alias Leywn.Mock.Config

  require Logger

  @names_key {__MODULE__, :names}
  @mock_key_prefix {__MODULE__, :mock}

  # A mock name reaches the filesystem as a path segment and comes back out in
  # URLs, so it is restricted to characters that can mean nothing else. In
  # particular this rejects "..", any name containing a separator, and dotfiles.
  @name_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/

  # Collection names are keys from the operator's own JSON file, but they are
  # also path segments, so they get the same treatment.
  @collection_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z/

  # /mocks/{name}/openapi.json is the mock's own spec. A collection by that name
  # would be shadowed by it and could never be read, so it is dropped at load
  # time rather than silently served as something else.
  @reserved_collections ~w(openapi.json)

  @doc """
  Load every mock from the configured directory and publish it.

  Returns the list of loaded mock names. Safe to call more than once; a reload
  replaces what was published before.
  """
  def load_all do
    dir = Config.mocks_dir()

    names =
      dir
      |> candidate_dirs()
      |> Enum.reduce([], fn name, acc ->
        case load_mock(dir, name) do
          {:ok, mock} ->
            :persistent_term.put(mock_key(name), mock)
            [name | acc]

          {:error, reason} ->
            Logger.warning("Mock #{inspect(name)} skipped: #{reason}")
            acc
        end
      end)
      |> Enum.reverse()

    :persistent_term.put(@names_key, names)
    names
  end

  @doc "Names of all successfully loaded mocks, in alphabetical order."
  def names, do: :persistent_term.get(@names_key, [])

  @doc """
  Fetch a loaded mock by name.

  Returns `{:ok, mock}` or `:error`. The name is validated before it is used as
  a lookup key so that a request path can never reach anything else.
  """
  def fetch(name) when is_binary(name) do
    if valid_name?(name) do
      case :persistent_term.get(mock_key(name), nil) do
        nil -> :error
        mock -> {:ok, mock}
      end
    else
      :error
    end
  end

  def fetch(_), do: :error

  @doc "True if the string is acceptable as a mock name."
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_pattern, name)
  def valid_name?(_), do: false

  # ---------------------------------------------------------------------------
  # Directory scanning
  # ---------------------------------------------------------------------------

  defp candidate_dirs(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.filter(&valid_name?/1)
        |> Enum.filter(&real_directory?(Path.join(dir, &1)))
        |> Enum.take(Config.max_mocks())

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.warning("Mocks directory #{inspect(dir)} could not be read: #{inspect(reason)}")
        []
    end
  end

  # lstat rather than stat: a symlink in the mocks directory could point
  # anywhere on the filesystem, and following it would let the directory layout
  # decide which files this process reads.
  defp real_directory?(path) do
    match?({:ok, %File.Stat{type: :directory}}, File.lstat(path))
  end

  # ---------------------------------------------------------------------------
  # Loading a single mock
  # ---------------------------------------------------------------------------

  defp load_mock(dir, name) do
    mock_dir = Path.join(dir, name)

    with {:ok, path} <- pick_file(mock_dir),
         {:ok, body} <- read_capped(path),
         {:ok, raw} <- decode(body),
         {:ok, collections, singletons} <- split(raw) do
      {:ok,
       %{
         name: name,
         file: path,
         collections: collections,
         singletons: singletons,
         collection_names: collections |> Map.keys() |> Enum.sort(),
         singleton_names: singletons |> Map.keys() |> Enum.sort()
       }}
    end
  end

  # "db.json" wins so a mock folder can hold a README or a schema alongside its
  # data. Without it, a folder must contain exactly one .json file — guessing
  # between several would make which dataset is served depend on sort order.
  defp pick_file(mock_dir) do
    case File.ls(mock_dir) do
      {:ok, entries} ->
        jsons =
          entries
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.filter(&regular_file?(Path.join(mock_dir, &1)))
          |> Enum.sort()

        cond do
          "db.json" in jsons -> {:ok, Path.join(mock_dir, "db.json")}
          length(jsons) == 1 -> {:ok, Path.join(mock_dir, hd(jsons))}
          jsons == [] -> {:error, "no .json file found"}
          true -> {:error, "several .json files and no db.json to choose between them"}
        end

      {:error, reason} ->
        {:error, "directory unreadable (#{inspect(reason)})"}
    end
  end

  defp regular_file?(path) do
    match?({:ok, %File.Stat{type: :regular}}, File.lstat(path))
  end

  # The size is checked through the file's own metadata before a single byte is
  # read, so an oversized file costs a stat rather than its own size in memory.
  defp read_capped(path) do
    max = Config.max_file_bytes()

    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > max ->
        {:error, "file is #{size} bytes, over the #{max} byte limit"}

      {:ok, _} ->
        case File.read(path) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, "file unreadable (#{inspect(reason)})"}
        end

      {:error, reason} ->
        {:error, "file unreadable (#{inspect(reason)})"}
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{} = raw} -> {:ok, raw}
      {:ok, _} -> {:error, "top level of the file must be a JSON object"}
      {:error, _} -> {:error, "file is not valid JSON"}
    end
  end

  # A key whose value is a list of objects becomes a collection (/users);
  # a key whose value is a single object becomes a singleton (/profile), the
  # same split json-server makes. Anything else is dropped rather than served
  # as something that would not behave like a REST resource.
  defp split(raw) do
    {collections, singletons} =
      raw
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.take(Config.max_collections())
      |> Enum.reduce({%{}, %{}}, fn {key, value}, {cols, singles} ->
        cond do
          not Regex.match?(@collection_pattern, key) or key in @reserved_collections ->
            {cols, singles}

          is_list(value) and Enum.all?(value, &is_map/1) ->
            {Map.put(cols, key, build_collection(value)), singles}

          is_map(value) ->
            {cols, Map.put(singles, key, value)}

          true ->
            {cols, singles}
        end
      end)

    if map_size(collections) == 0 and map_size(singletons) == 0 do
      {:error, "no usable collections found"}
    else
      {:ok, collections, singletons}
    end
  end

  # Alongside the records, an id index is precomputed so a by-id read is a map
  # lookup rather than a scan of the list, and the id shape is recorded so
  # generated ids match the ones already in the file.
  defp build_collection(records) do
    index =
      Enum.reduce(records, %{}, fn record, acc ->
        case Map.fetch(record, "id") do
          {:ok, id} -> Map.put_new(acc, id_key(id), record)
          :error -> acc
        end
      end)

    ids = Enum.map(records, &Map.get(&1, "id"))

    %{
      records: records,
      index: index,
      id_type: id_type(ids),
      max_int_id: ids |> Enum.filter(&is_integer/1) |> Enum.max(fn -> 0 end)
    }
  end

  defp id_type([]), do: :none

  defp id_type(ids) do
    cond do
      Enum.all?(ids, &is_integer/1) -> :integer
      Enum.all?(ids, &is_binary/1) -> :string
      true -> :mixed
    end
  end

  @doc """
  Normalise an id to the string used as an index key.

  A record with `"id": 1` has to be reachable at `/posts/1`, where the path
  segment is the string `"1"`; indexing both under the same key is what makes
  integer and string ids behave identically on the way in.
  """
  def id_key(id) when is_binary(id), do: id
  def id_key(id) when is_integer(id), do: Integer.to_string(id)
  def id_key(id) when is_float(id), do: Float.to_string(id)
  def id_key(id), do: inspect(id)

  defp mock_key(name), do: {@mock_key_prefix, name}
end
