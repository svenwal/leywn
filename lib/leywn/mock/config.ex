defmodule Leywn.Mock.Config do
  @moduledoc """
  Every tunable of the mock subsystem, in one place.

  Each limit exists because the mock endpoints are the only part of Leywn that
  accepts writes and keeps state between requests, which makes them the only
  part with a memory-growth surface an anonymous caller can push on. The
  defaults are deliberately small: a demo backend needs enough room to show a
  CRUD flow, not enough to store a workload.

  Values are read from the environment on every call rather than cached, so a
  test can set one with `System.put_env/2` without restarting the application.
  Each read is a single ETS lookup in the environment table, which is
  negligible next to the JSON encoding that follows it.
  """

  @doc "Directory holding one subfolder per mock."
  def mocks_dir do
    case System.get_env("LEYWN_MOCKS_DIR") do
      nil -> Application.app_dir(:leywn, "priv/mocks")
      "" -> Application.app_dir(:leywn, "priv/mocks")
      dir -> dir
    end
  end

  @doc "When true, only GET is served and no state is ever created."
  def readonly?, do: System.get_env("LEYWN_MOCK_READONLY") == "true"

  @doc "Mutating requests per minute, per client IP."
  def write_rate_limit, do: int_env("LEYWN_MOCK_WRITE_RATE_LIMIT", 60)

  @doc """
  Mutating requests per minute across all clients.

  The per-IP bucket alone is not a defence: an attacker with a thousand source
  addresses gets a thousand times the budget. This ceiling is what actually
  bounds the write rate, and therefore how fast the overlay can be filled.
  """
  def global_write_rate_limit, do: int_env("LEYWN_MOCK_WRITE_RATE_LIMIT_GLOBAL", 600)

  @doc "Number of per-IP buckets the rate limiter will track before falling back to the global bucket."
  def rate_limit_buckets, do: int_env("LEYWN_MOCK_RATE_BUCKETS", 10_000)

  @doc "Maximum overlay entries (creates, updates and deletes) per mock."
  def max_new_entries, do: int_env("LEYWN_MOCK_MAX_NEW_ENTRIES", 100)

  @doc """
  Seconds after which an overlay entry is forgotten.

  This is the property that makes the whole subsystem safe to leave exposed:
  state is a lease, not a store, so anything an attacker manages to write is
  reclaimed without operator involvement.
  """
  def entry_ttl_seconds, do: int_env("LEYWN_MOCK_ENTRY_TTL_SECONDS", 300)

  @doc "Maximum request body accepted by a mutating mock request."
  def max_body_bytes, do: int_env("LEYWN_MOCK_MAX_BODY_BYTES", 16_384)

  @doc """
  Maximum total bytes of overlay state across all mocks.

  An entry count alone does not bound memory — a hundred entries of 16 KiB each
  is 1.6 MiB per mock and scales with the number of mounted mocks. This is the
  hard ceiling on what the feature can ever hold.
  """
  def max_overlay_bytes, do: int_env("LEYWN_MOCK_MAX_OVERLAY_BYTES", 1_048_576)

  @doc "Maximum records returned by a single collection read."
  def max_page_size, do: int_env("LEYWN_MOCK_MAX_PAGE_SIZE", 200)

  @doc "Maximum size of a mock's JSON file. Larger files are skipped with a warning at startup."
  def max_file_bytes, do: int_env("LEYWN_MOCK_MAX_FILE_BYTES", 8_388_608)

  @doc "Maximum number of mocks loaded from the mocks directory."
  def max_mocks, do: int_env("LEYWN_MOCK_MAX_MOCKS", 50)

  @doc "Maximum number of collections within a single mock."
  def max_collections, do: int_env("LEYWN_MOCK_MAX_COLLECTIONS", 100)

  @doc """
  Maximum nesting depth of a write body.

  Jason imposes no depth limit of its own, so `[[[[...]]]]` is decoded as
  written; a deeply nested term then costs far more to walk and re-encode than
  its byte size suggests.
  """
  def max_depth, do: int_env("LEYWN_MOCK_MAX_DEPTH", 16)

  @doc "Maximum number of keys in any single object of a write body."
  def max_keys, do: int_env("LEYWN_MOCK_MAX_KEYS", 100)

  @doc "Maximum number of query parameters honoured as field filters on a read."
  def max_filters, do: int_env("LEYWN_MOCK_MAX_FILTERS", 10)

  defp int_env(var, default) do
    with value when is_binary(value) <- System.get_env(var),
         {n, ""} <- Integer.parse(String.trim(value)),
         true <- n >= 0 do
      n
    else
      _ -> default
    end
  end
end
