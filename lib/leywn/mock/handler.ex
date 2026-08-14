defmodule Leywn.Mock.Handler do
  @moduledoc """
  Serves every request under `/mocks`.

  Reads behave like json-server: a collection lists its records, an id addresses
  one of them, and `/{collection}/{id}/{child}` follows the foreign key between
  two collections. Writes behave like json-server too, except that what they
  create is a lease — see `Leywn.Mock.Store` — and every one of them is charged
  against a rate limit first.

  The order of checks on a mutating request is deliberate: read-only mode, then
  the rate limit, then resolving the target, and only then reading the body.
  Each step is cheaper than the one after it, so a request that will be
  rejected is rejected before it has cost anything worth measuring.
  """

  import Plug.Conn

  alias Leywn.Mock.{Config, Data, Inflect, Loader, OpenAPI, RateLimit, Store}

  # Comparison suffixes, longest first so that "_gte" is recognised before the
  # "_gt" it starts with.
  @operators ["_gte", "_lte", "_ne", "_like", "_gt", "_lt"]

  # A needle is compared against every string value of every record, so its
  # length is bounded rather than left to the caller.
  @max_search_length 128

  @doc """
  Dispatch a request whose path is `/mocks/<segments>`.
  """
  def handle(conn, segments) do
    conn = fetch_query_params(conn)

    case segments do
      [] ->
        index(conn)

      [mock] ->
        with_mock(conn, mock, &mock_root/2)

      [mock, "openapi.json"] ->
        with_mock(conn, mock, &openapi/2)

      [mock, resource] ->
        with_mock(conn, mock, &resource(&1, &2, resource))

      [mock, collection, id] ->
        with_mock(conn, mock, &item(&1, &2, collection, id))

      [mock, collection, id, child] ->
        with_mock(conn, mock, &nested(&1, &2, collection, id, child))

      _ ->
        not_found(conn, "mock_path_not_found")
    end
  end

  defp with_mock(conn, name, fun) do
    case Loader.fetch(name) do
      {:ok, mock} -> fun.(conn, mock)
      :error -> not_found(conn, "mock_not_found", %{mock: name})
    end
  end

  # ---------------------------------------------------------------------------
  # Discovery
  # ---------------------------------------------------------------------------

  defp index(%{method: "GET"} = conn) do
    mocks =
      for name <- Loader.names(), {:ok, mock} <- [Loader.fetch(name)] do
        %{
          name: name,
          url: "/mocks/#{name}",
          openapi_url: "/mocks/#{name}/openapi.json",
          docs_url: "/docs/mocks/#{name}",
          collections: mock.collection_names,
          singletons: mock.singleton_names
        }
      end

    respond(conn, 200, %{count: length(mocks), mocks: mocks}, "mocks")
  end

  defp index(conn), do: method_not_allowed(conn, ["GET"])

  # The whole dataset is deliberately not served here. A mounted file may be
  # megabytes, and a route that re-encodes all of it on every request is an
  # amplification target; the per-collection routes below page their output.
  defp mock_root(%{method: "GET"} = conn, mock) do
    collections =
      for name <- mock.collection_names do
        %{
          name: name,
          records: length(Data.list(mock, name)),
          url: "/mocks/#{mock.name}/#{name}"
        }
      end

    singletons =
      for name <- mock.singleton_names do
        %{name: name, url: "/mocks/#{mock.name}/#{name}"}
      end

    data = %{
      mock: mock.name,
      source_file: Path.basename(mock.file),
      collections: collections,
      singletons: singletons,
      openapi_url: "/mocks/#{mock.name}/openapi.json",
      docs_url: "/docs/mocks/#{mock.name}",
      writes: %{
        enabled: not Config.readonly?(),
        entries_used: Store.count(mock.name),
        max_new_entries: Config.max_new_entries(),
        entry_ttl_seconds: Config.entry_ttl_seconds(),
        rate_limit_per_minute: Config.write_rate_limit()
      }
    }

    respond(conn, 200, data, "mock")
  end

  defp mock_root(conn, _mock), do: method_not_allowed(conn, ["GET"])

  defp openapi(%{method: "GET"} = conn, mock) do
    spec = OpenAPI.build(mock, Leywn.Servers.servers(conn))

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(spec))
  end

  defp openapi(conn, _mock), do: method_not_allowed(conn, ["GET"])

  # ---------------------------------------------------------------------------
  # Collections and singletons
  # ---------------------------------------------------------------------------

  defp resource(conn, mock, name) do
    cond do
      Data.collection?(mock, name) -> collection(conn, mock, name)
      Data.singleton?(mock, name) -> singleton(conn, mock, name)
      true -> not_found(conn, "collection_not_found", %{mock: mock.name, collection: name})
    end
  end

  defp collection(%{method: "GET"} = conn, mock, name) do
    send_list(conn, Data.list(mock, name), name)
  end

  defp collection(%{method: "POST"} = conn, mock, name) do
    with :ok <- allow_writes(conn),
         {:ok, conn, body} <- read_json_object(conn) do
      create(conn, mock, name, body)
    else
      {:halt, conn} -> conn
    end
  end

  defp collection(conn, _mock, _name),
    do: method_not_allowed(conn, write_methods(["GET", "POST"]))

  # Single-object resources have no id to address, and giving them write
  # semantics would mean a second, differently shaped mutation path for no real
  # gain. They are read-only, and say so.
  defp singleton(%{method: "GET"} = conn, mock, name) do
    respond(conn, 200, Map.fetch!(mock.singletons, name), name)
  end

  defp singleton(conn, _mock, _name), do: method_not_allowed(conn, ["GET"])

  # ---------------------------------------------------------------------------
  # Items
  # ---------------------------------------------------------------------------

  defp item(conn, mock, collection, id) do
    if Data.collection?(mock, collection) do
      dispatch_item(conn, mock, collection, id)
    else
      not_found(conn, "collection_not_found", %{mock: mock.name, collection: collection})
    end
  end

  defp dispatch_item(%{method: "GET"} = conn, mock, collection, id) do
    case Data.get(mock, collection, id) do
      {:ok, record} -> respond(conn, 200, record, singular(collection))
      :error -> not_found(conn, "record_not_found", %{collection: collection, id: id})
    end
  end

  defp dispatch_item(%{method: method} = conn, mock, collection, id)
       when method in ["PUT", "PATCH"] do
    with :ok <- allow_writes(conn),
         {:ok, conn, body} <- read_json_object(conn) do
      case Data.get(mock, collection, id) do
        {:ok, existing} ->
          merged = if method == "PATCH", do: Map.merge(existing, body), else: body
          # The id belongs to the resource, not to the payload: a body that
          # omits it, or carries a different one, must not move or rename the
          # record the URL addressed.
          record = Map.put(merged, "id", Map.get(existing, "id", id))
          store(conn, mock, collection, id, record, 200, singular(collection))

        :error ->
          not_found(conn, "record_not_found", %{collection: collection, id: id})
      end
    else
      {:halt, conn} -> conn
    end
  end

  defp dispatch_item(%{method: "DELETE"} = conn, mock, collection, id) do
    case allow_writes(conn) do
      :ok ->
        case Data.get(mock, collection, id) do
          {:ok, record} ->
            case Store.delete(mock.name, collection, id) do
              :ok -> respond(conn, 200, record, singular(collection))
              {:error, reason} -> storage_full(conn, reason)
            end

          :error ->
            not_found(conn, "record_not_found", %{collection: collection, id: id})
        end

      {:halt, conn} ->
        conn
    end
  end

  defp dispatch_item(conn, _mock, _collection, _id),
    do: method_not_allowed(conn, write_methods(["GET", "PUT", "PATCH", "DELETE"]))

  defp nested(%{method: "GET"} = conn, mock, collection, id, child) do
    with true <- Data.collection?(mock, collection),
         {:ok, _record} <- Data.get(mock, collection, id),
         records when is_list(records) <- Data.related(mock, collection, id, child) do
      # Related records go through the same pipeline as a plain collection read.
      # A relation is often the larger of the two sides — the availability of one
      # property, the bookings of one flight — so leaving it unpaged and
      # unfilterable would be both surprising and the one unbounded read left.
      send_list(conn, records, child)
    else
      false ->
        not_found(conn, "collection_not_found", %{mock: mock.name, collection: collection})

      :error ->
        not_found(conn, "record_not_found", %{collection: collection, id: id})

      nil ->
        not_found(conn, "relation_not_found", %{
          parent: collection,
          child: child,
          detail: "#{child} has no field referencing #{singular(collection)}"
        })
    end
  end

  defp nested(conn, _mock, _collection, _id, _child), do: method_not_allowed(conn, ["GET"])

  # ---------------------------------------------------------------------------
  # Writing
  # ---------------------------------------------------------------------------

  defp create(conn, mock, collection, body) do
    if Data.collection?(mock, collection) do
      taken? = fn key -> Data.get(mock, collection, key) != :error end

      case Map.fetch(body, "id") do
        {:ok, given} when is_binary(given) or is_integer(given) ->
          key = Loader.id_key(given)

          if taken?.(key) do
            respond(conn, 409, %{error: "id_conflict", collection: collection, id: key}, "error")
          else
            insert(conn, mock, collection, given, body)
          end

        {:ok, _other} ->
          unprocessable(conn, "invalid_id", %{
            detail: "id must be a string or an integer"
          })

        :error ->
          insert(conn, mock, collection, Data.next_id(mock, collection, taken?), body)
      end
    else
      not_found(conn, "collection_not_found", %{mock: mock.name, collection: collection})
    end
  end

  defp insert(conn, mock, collection, id, body) do
    key = Loader.id_key(id)
    record = Map.put(body, "id", id)

    conn
    |> put_resp_header("location", "/mocks/#{mock.name}/#{collection}/#{key}")
    |> store(mock, collection, key, record, 201, singular(collection))
  end

  defp store(conn, mock, collection, key, record, status, root) do
    case Store.put(mock.name, collection, key, record) do
      :ok -> respond(conn, status, record, root)
      {:error, reason} -> storage_full(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Read query parameters
  # ---------------------------------------------------------------------------

  # The single path every list response takes, whether it came from a collection
  # or from following a relation.
  defp send_list(conn, records, root) do
    with {:ok, filtered} <- apply_filters(records, conn.query_params),
         {:ok, sorted} <- apply_sort(filtered, conn.query_params),
         {:ok, page, limit} <- pagination(conn.query_params) do
      total = length(sorted)
      slice = Enum.slice(sorted, (page - 1) * limit, limit)

      conn
      |> put_page_headers(total, page, limit)
      |> respond(200, slice, root)
    else
      {:error, error, detail} -> bad_request(conn, error, detail)
    end
  end

  # Any parameter that is not one of the reserved underscore-prefixed controls
  # is a filter on a field. Plain `?city=Barcelona` is equality; a recognised
  # suffix makes it a comparison, following json-server's convention:
  #
  #     ?maxGuests_gte=4          at least four guests
  #     ?checkIn_gte=2026-09-01   ISO dates order correctly as strings
  #     ?name_like=villa          case-insensitive substring, never a regex
  #
  # `q` searches every string value of a record at once.
  defp apply_filters(records, params) do
    {search, rest} = Map.pop(params, "q")

    filters =
      rest
      |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_") end)
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)

    count = length(filters) + if(is_binary(search), do: 1, else: 0)

    cond do
      count > Config.max_filters() ->
        {:error, "too_many_filters", %{maximum: Config.max_filters(), provided: count}}

      is_binary(search) and String.length(search) > @max_search_length ->
        {:error, "search_too_long", %{maximum_length: @max_search_length}}

      true ->
        matchers = Enum.map(filters, &compile_filter/1)

        {:ok,
         records
         |> Enum.filter(fn record -> Enum.all?(matchers, & &1.(record)) end)
         |> search(search)}
    end
  end

  defp search(records, nil), do: records
  defp search(records, ""), do: records

  defp search(records, needle) do
    needle = String.downcase(needle)

    Enum.filter(records, fn record ->
      Enum.any?(record, fn {_key, value} -> contains_text?(value, needle, 1) end)
    end)
  end

  # Searching only the scalar fields would miss the interesting half of most
  # records: `amenities: ["wifi", "ski_storage"]` is precisely what someone
  # typing "ski" is looking for. Lists and nested objects are walked, with the
  # same depth ceiling that bounds write bodies.
  defp contains_text?(value, needle, depth) when is_list(value) or is_map(value) do
    if depth > Config.max_depth() do
      false
    else
      values = if is_map(value), do: Map.values(value), else: value
      Enum.any?(values, &contains_text?(&1, needle, depth + 1))
    end
  end

  defp contains_text?(value, needle, _depth) do
    case to_comparable(value) do
      nil -> false
      text -> String.contains?(String.downcase(text), needle)
    end
  end

  # The parameter is turned into a predicate once, before the scan, rather than
  # re-parsed for every record.
  defp compile_filter({key, value}) do
    case Enum.find(@operators, &String.ends_with?(key, &1)) do
      nil ->
        fn record -> to_comparable(Map.get(record, key)) == value end

      operator ->
        field = String.replace_suffix(key, operator, "")
        fn record -> compare(Map.get(record, field), operator, value) end
    end
  end

  defp compare(nil, _operator, _value), do: false

  # `_like` walks lists too, so `?amenities_like=pool` matches a record whose
  # amenities array contains it — the same reach `q` has, narrowed to one field.
  defp compare(field_value, "_like", value) do
    contains_text?(field_value, String.downcase(value), 1)
  end

  defp compare(field_value, operator, value) do
    case coerce(field_value, value) do
      :incomparable ->
        false

      {left, right} ->
        case operator do
          "_gte" -> left >= right
          "_lte" -> left <= right
          "_gt" -> left > right
          "_lt" -> left < right
          "_ne" -> left != right
        end
    end
  end

  # Numbers compare numerically, everything else as strings. That is what makes
  # `?seatsAvailable_gte=4` and `?departureTime_gte=2026-09-05` both behave the
  # way a caller expects: ISO-8601 timestamps already order lexicographically.
  defp coerce(field_value, query_value) when is_number(field_value) do
    case Float.parse(query_value) do
      {number, ""} -> {field_value / 1, number}
      _ -> string_pair(field_value, query_value)
    end
  end

  defp coerce(field_value, query_value), do: string_pair(field_value, query_value)

  defp string_pair(field_value, query_value) do
    case to_comparable(field_value) do
      nil -> :incomparable
      text -> {text, query_value}
    end
  end

  defp apply_sort(records, params) do
    case Map.get(params, "_sort") do
      nil ->
        {:ok, records}

      field when is_binary(field) ->
        order = Map.get(params, "_order", "asc")

        if order in ["asc", "desc"] do
          sorted = Enum.sort_by(records, &sort_key(Map.get(&1, field)))
          {:ok, if(order == "desc", do: Enum.reverse(sorted), else: sorted)}
        else
          {:error, "invalid_order", %{allowed: ["asc", "desc"], provided: order}}
        end

      _ ->
        {:error, "invalid_sort", %{detail: "_sort must be a single field name"}}
    end
  end

  # Sorting a heterogeneous column must not crash. The leading integer groups
  # values by type so that numbers, strings and everything else form separate
  # ordered runs rather than being compared against each other by term order.
  defp sort_key(value) when is_number(value), do: {0, value, ""}
  defp sort_key(value) when is_binary(value), do: {1, 0, value}
  defp sort_key(nil), do: {3, 0, ""}
  defp sort_key(value), do: {2, 0, inspect(value)}

  # A collection read is capped rather than unbounded: the built-in dataset is
  # small, but a mounted file need not be, and re-encoding thousands of records
  # per request is exactly the kind of cheap-request/expensive-response
  # asymmetry worth closing off.
  defp pagination(params) do
    max = Config.max_page_size()

    with {:ok, page} <- positive_int(params, "_page", 1),
         {:ok, limit} <- positive_int(params, "_limit", max) do
      cond do
        page < 1 -> {:error, "invalid_page", %{minimum: 1, provided: page}}
        limit < 1 -> {:error, "invalid_limit", %{minimum: 1, provided: limit}}
        limit > max -> {:error, "limit_too_large", %{maximum: max, provided: limit}}
        true -> {:ok, page, limit}
      end
    end
  end

  defp positive_int(params, key, default) do
    case Map.get(params, key) do
      nil ->
        {:ok, default}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {n, ""} -> {:ok, n}
          _ -> {:error, "invalid_#{String.trim_leading(key, "_")}", %{provided: value}}
        end

      _ ->
        {:error, "invalid_#{String.trim_leading(key, "_")}", %{detail: "expected a single value"}}
    end
  end

  defp put_page_headers(conn, total, page, limit) do
    conn
    |> put_resp_header("x-total-count", Integer.to_string(total))
    |> put_resp_header("x-page", Integer.to_string(page))
    |> put_resp_header("x-page-size", Integer.to_string(limit))
    |> put_resp_header("x-total-pages", Integer.to_string(max(ceil(total / limit), 1)))
    # Without this the browser hands JavaScript none of the headers above.
    |> put_resp_header(
      "access-control-expose-headers",
      "x-total-count, x-page, x-page-size, x-total-pages"
    )
  end

  defp to_comparable(value) when is_binary(value), do: value
  defp to_comparable(value) when is_integer(value), do: Integer.to_string(value)
  defp to_comparable(value) when is_float(value), do: Float.to_string(value)
  defp to_comparable(true), do: "true"
  defp to_comparable(false), do: "false"
  defp to_comparable(nil), do: nil
  defp to_comparable(_), do: nil

  # ---------------------------------------------------------------------------
  # Write guards
  # ---------------------------------------------------------------------------

  defp allow_writes(conn) do
    if Config.readonly?() do
      {:halt, method_not_allowed(conn, ["GET"], "mock_read_only")}
    else
      case RateLimit.check(conn) do
        :ok ->
          :ok

        {:error, :rate_limited, retry_after} ->
          {:halt,
           conn
           |> put_resp_header("retry-after", Integer.to_string(retry_after))
           |> respond(
             429,
             %{
               error: "rate_limited",
               detail: "too many mutating requests",
               limit_per_minute: Config.write_rate_limit(),
               global_limit_per_minute: Config.global_write_rate_limit(),
               retry_after_seconds: retry_after
             },
             "error"
           )}
      end
    end
  end

  defp read_json_object(conn) do
    max = Config.max_body_bytes()

    case read_body(conn, length: max, read_length: min(8_000, max(max, 1))) do
      {:ok, body, conn} ->
        case decode_object(body) do
          {:ok, object} -> {:ok, conn, object}
          {:error, error, detail} -> {:halt, unprocessable(conn, error, detail)}
        end

      {:more, _partial, conn} ->
        {:halt,
         respond(
           conn,
           413,
           %{error: "payload_too_large", maximum_bytes: max},
           "error"
         )}

      {:error, _reason} ->
        {:halt, bad_request(conn, "could_not_read_body", %{})}
    end
  end

  defp decode_object(body) do
    case Jason.decode(body) do
      {:ok, %{} = object} -> check_shape(object, 1)
      {:ok, _other} -> {:error, "invalid_body", %{detail: "body must be a JSON object"}}
      {:error, _} -> {:error, "invalid_json", %{detail: "body is not valid JSON"}}
    end
  end

  # Byte size alone does not bound what a payload costs. Jason imposes no depth
  # limit of its own, so a body well inside the size cap can still nest deeply
  # enough that walking and re-encoding it costs far more than its length
  # suggests. Depth and key count are checked before the term is stored.
  defp check_shape(value, depth) do
    cond do
      depth > Config.max_depth() ->
        {:error, "body_too_deep", %{maximum_depth: Config.max_depth()}}

      is_map(value) and map_size(value) > Config.max_keys() ->
        {:error, "too_many_keys", %{maximum_keys: Config.max_keys(), provided: map_size(value)}}

      is_map(value) ->
        Enum.reduce_while(Map.values(value), {:ok, value}, fn child, acc ->
          case check_shape(child, depth + 1) do
            {:ok, _} -> {:cont, acc}
            error -> {:halt, error}
          end
        end)

      is_list(value) ->
        Enum.reduce_while(value, {:ok, value}, fn child, acc ->
          case check_shape(child, depth + 1) do
            {:ok, _} -> {:cont, acc}
            error -> {:halt, error}
          end
        end)

      true ->
        {:ok, value}
    end
  end

  # ---------------------------------------------------------------------------
  # Responses
  # ---------------------------------------------------------------------------

  defp respond(conn, status, data, root), do: Leywn.Respond.send(conn, status, data, root: root)

  defp not_found(conn, error, extra \\ %{}) do
    respond(conn, 404, Map.merge(%{error: error}, extra), "error")
  end

  defp bad_request(conn, error, extra) do
    respond(conn, 400, Map.merge(%{error: error}, extra), "error")
  end

  defp unprocessable(conn, error, extra) do
    respond(conn, 422, Map.merge(%{error: error}, extra), "error")
  end

  defp storage_full(conn, :too_many_entries) do
    respond(
      conn,
      507,
      %{
        error: "mock_storage_full",
        detail: "this mock already holds the maximum number of changes",
        max_new_entries: Config.max_new_entries(),
        entry_ttl_seconds: Config.entry_ttl_seconds()
      },
      "error"
    )
  end

  defp storage_full(conn, :overlay_full) do
    respond(
      conn,
      507,
      %{
        error: "mock_storage_full",
        detail: "the total size of all mock changes is at its limit",
        max_overlay_bytes: Config.max_overlay_bytes(),
        entry_ttl_seconds: Config.entry_ttl_seconds()
      },
      "error"
    )
  end

  defp method_not_allowed(conn, allowed, error \\ "method_not_allowed") do
    conn
    |> put_resp_header("allow", Enum.join(allowed, ", "))
    |> respond(405, %{error: error, allowed: allowed}, "error")
  end

  defp write_methods(methods) do
    if Config.readonly?(), do: ["GET"], else: methods
  end

  # "users" addresses the collection; a single one of them is a "user". Used
  # only as the XML root element for a single record, where <users> around one
  # record would read as a list of them.
  defp singular(collection), do: Inflect.singular(collection)
end
