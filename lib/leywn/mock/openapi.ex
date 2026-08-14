defmodule Leywn.Mock.OpenAPI do
  @moduledoc """
  Renders an OpenAPI 3.0.3 document for one mock, derived from its data.

  Nothing here is hand-maintained: paths come from the collections the file
  declares, schemas are inferred from the records themselves, and examples are
  real records rather than invented ones. A mock mounted into the container
  therefore arrives with documentation without its author writing any.

  The document describes the installation as it is actually running: with
  `LEYWN_MOCK_READONLY=true` the write operations are absent rather than
  documented and rejected, and with `LEYWN_ONLY_JSON=true` the XML response
  variants are absent too.
  """

  alias Leywn.Mock.{Config, Data}

  # Enough records to see which fields exist and which are merely absent from
  # the first one, without walking a file that may hold thousands.
  @sample_size 20

  def build(mock, servers) do
    %{
      "openapi" => "3.0.3",
      "info" => info(mock),
      "servers" => servers,
      "tags" => tags(mock),
      "paths" => paths(mock),
      "components" => %{"schemas" => schemas(mock)}
    }
  end

  # ---------------------------------------------------------------------------
  # Info and tags
  # ---------------------------------------------------------------------------

  defp info(mock) do
    %{
      "title" => "Leywn mock: #{mock.name}",
      "version" => Application.spec(:leywn, :vsn) |> to_string(),
      "description" => description(mock)
    }
  end

  defp description(mock) do
    base = """
    A mock REST API served by Leywn from `#{Path.basename(mock.file)}`.

    Every collection supports the usual read operations. `_page` and `_limit`
    page the result (at most #{Config.max_page_size()} records per response,
    with the unpaged total in the `X-Total-Count` header), `_sort` and `_order`
    order it, and any other query parameter filters on a field of that name —
    `?userId=a1b2c3d4` returns only the records whose `userId` matches.

    Filters also take comparison suffixes: `?maxGuests_gte=4` for at least four,
    `?checkIn_gte=2026-09-01` for a date range (ISO-8601 values order correctly
    as text), `?name_like=villa` for a case-insensitive substring, and `_lte`,
    `_gt`, `_lt` and `_ne` alongside them. `?q=barcelona` searches every field of
    a record at once.
    """

    writes =
      if Config.readonly?() do
        """

        This installation runs with `LEYWN_MOCK_READONLY=true`, so the mock is
        read-only and only the operations below are available.
        """
      else
        """

        Writes are held in memory, never on disk, and are **forgotten after
        #{Config.entry_ttl_seconds()} seconds** — after which the underlying
        file data reads back unchanged. Each mock holds at most
        #{Config.max_new_entries()} changes at a time, and mutating requests are
        limited to #{Config.write_rate_limit()} per minute per client. Restarting
        Leywn discards everything written.
        """
      end

    base <> writes
  end

  defp tags(mock) do
    resources =
      for name <- mock.collection_names ++ mock.singleton_names do
        %{"name" => name, "description" => "The #{name} resource"}
      end

    [%{"name" => "_meta", "description" => "About this mock"} | resources]
  end

  # ---------------------------------------------------------------------------
  # Paths
  # ---------------------------------------------------------------------------

  defp paths(mock) do
    root = %{"/mocks/#{mock.name}" => %{"get" => overview_op()}}

    Enum.reduce(mock.collection_names, root, fn name, acc ->
      acc
      |> Map.put("/mocks/#{mock.name}/#{name}", collection_ops(mock, name))
      |> Map.put("/mocks/#{mock.name}/#{name}/{id}", item_ops(mock, name))
      |> Map.merge(nested_paths(mock, name))
    end)
    |> Map.merge(singleton_paths(mock))
  end

  defp overview_op do
    %{
      "tags" => ["_meta"],
      "summary" => "Describe this mock — its collections, record counts and write limits",
      "responses" => %{"200" => json_response("Success", %{"type" => "object"}, nil)}
    }
  end

  defp collection_ops(mock, name) do
    schema = ref(name)
    example = sample_record(mock, name)

    get = %{
      "tags" => [name],
      "summary" => "List #{name}",
      "parameters" => list_parameters(mock, name),
      "responses" => %{
        "200" =>
          json_response(
            "A page of #{name}",
            %{"type" => "array", "items" => schema},
            example && [example]
          ),
        "400" => error_response("Invalid paging, sorting or filter parameters")
      }
    }

    if Config.readonly?() do
      %{"get" => get}
    else
      %{
        "get" => get,
        "post" => %{
          "tags" => [name],
          "summary" => "Create a #{singular(name)}",
          "description" =>
            "Held in memory and forgotten after #{Config.entry_ttl_seconds()} seconds. " <>
              "An `id` is generated when the body does not supply one.",
          "requestBody" => request_body(example, drop_id: true),
          "responses" => %{
            "201" => json_response("Created", schema, example),
            "409" => error_response("A record with the supplied id already exists"),
            "413" => error_response("Body larger than #{Config.max_body_bytes()} bytes"),
            "422" => error_response("Body is not a JSON object, or is too deeply nested"),
            "429" => error_response("Write rate limit exceeded"),
            "507" => error_response("This mock already holds its maximum number of changes")
          }
        }
      }
    end
  end

  defp item_ops(mock, name) do
    schema = ref(name)
    example = sample_record(mock, name)
    id_param = [path_id_parameter(mock, name)]

    get = %{
      "tags" => [name],
      "summary" => "Fetch one #{singular(name)} by id",
      "parameters" => id_param,
      "responses" => %{
        "200" => json_response("Success", schema, example),
        "404" => error_response("No #{singular(name)} with that id")
      }
    }

    if Config.readonly?() do
      %{"get" => get}
    else
      write_responses = %{
        "200" => json_response("Success", schema, example),
        "404" => error_response("No #{singular(name)} with that id"),
        "413" => error_response("Body larger than #{Config.max_body_bytes()} bytes"),
        "422" => error_response("Body is not a JSON object, or is too deeply nested"),
        "429" => error_response("Write rate limit exceeded"),
        "507" => error_response("This mock already holds its maximum number of changes")
      }

      %{
        "get" => get,
        "put" => %{
          "tags" => [name],
          "summary" => "Replace a #{singular(name)}",
          "description" => "The id in the path wins; one in the body is ignored.",
          "parameters" => id_param,
          "requestBody" => request_body(example, drop_id: true),
          "responses" => write_responses
        },
        "patch" => %{
          "tags" => [name],
          "summary" => "Update some fields of a #{singular(name)}",
          "parameters" => id_param,
          "requestBody" => request_body(patch_example(example), drop_id: true),
          "responses" => write_responses
        },
        "delete" => %{
          "tags" => [name],
          "summary" => "Delete a #{singular(name)}",
          "description" =>
            "Returns the record that was removed. The deletion is itself forgotten after " <>
              "#{Config.entry_ttl_seconds()} seconds, at which point the record reappears.",
          "parameters" => id_param,
          "responses" => Map.drop(write_responses, ["413", "422"])
        }
      }
    end
  end

  # A nested route is advertised only where the data actually supports it, so
  # the spec never documents a path that answers 404.
  defp nested_paths(mock, parent) do
    for child <- mock.collection_names,
        child != parent,
        records = Data.list(mock, child),
        key = Data.relation_key(records, parent),
        is_binary(key),
        into: %{} do
      {"/mocks/#{mock.name}/#{parent}/{id}/#{child}",
       %{
         "get" => %{
           "tags" => [parent],
           "summary" => "List the #{child} of one #{singular(parent)}",
           "description" => "Matched on the `#{key}` field of #{child}.",
           "parameters" => [path_id_parameter(mock, parent)],
           "responses" => %{
             "200" =>
               json_response(
                 "Related #{child}",
                 %{"type" => "array", "items" => ref(child)},
                 nil
               ),
             "404" => error_response("No #{singular(parent)} with that id")
           }
         }
       }}
    end
  end

  defp singleton_paths(mock) do
    for name <- mock.singleton_names, into: %{} do
      {"/mocks/#{mock.name}/#{name}",
       %{
         "get" => %{
           "tags" => [name],
           "summary" => "Fetch #{name}",
           "responses" => %{
             "200" => json_response("Success", ref(name), Map.fetch!(mock.singletons, name))
           }
         }
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Parameters
  # ---------------------------------------------------------------------------

  defp list_parameters(mock, name) do
    paging = [
      query_param("_page", "integer", "1-based page number", 1),
      query_param(
        "_limit",
        "integer",
        "Records per page (maximum #{Config.max_page_size()})",
        Config.max_page_size()
      ),
      query_param("_sort", "string", "Field to sort by", nil),
      query_param("_order", "string", "Sort direction: asc or desc", "asc"),
      query_param(
        "q",
        "string",
        "Case-insensitive substring search across every field of a record",
        nil
      )
    ]

    # One parameter per field rather than six: enumerating every operator would
    # bury the fields themselves under five near-identical entries each.
    filters =
      mock
      |> field_names(name)
      |> Enum.take(Config.max_filters())
      |> Enum.map(fn field ->
        query_param(
          field,
          "string",
          "Return only records whose `#{field}` equals this. Comparison suffixes also " <>
            "work: `#{field}_gte`, `#{field}_lte`, `#{field}_gt`, `#{field}_lt`, " <>
            "`#{field}_ne`, and `#{field}_like` for a case-insensitive substring match.",
          nil
        )
      end)

    paging ++ filters
  end

  defp query_param(name, type, description, default) do
    schema = %{"type" => type}
    schema = if is_nil(default), do: schema, else: Map.put(schema, "default", default)

    %{
      "name" => name,
      "in" => "query",
      "required" => false,
      "description" => description,
      "schema" => schema
    }
  end

  defp path_id_parameter(mock, name) do
    {type, example} =
      case Map.fetch!(mock.collections, name) do
        %{id_type: :integer, records: records} -> {"integer", first_id(records)}
        %{records: records} -> {"string", first_id(records)}
      end

    param = %{
      "name" => "id",
      "in" => "path",
      "required" => true,
      "description" => "Identifier of the #{singular(name)}",
      "schema" => %{"type" => type}
    }

    if is_nil(example), do: param, else: Map.put(param, "example", example)
  end

  defp first_id([%{"id" => id} | _]), do: id
  defp first_id(_), do: nil

  # ---------------------------------------------------------------------------
  # Bodies and responses
  # ---------------------------------------------------------------------------

  defp request_body(nil, _opts) do
    %{
      "required" => true,
      "content" => %{"application/json" => %{"schema" => %{"type" => "object"}}}
    }
  end

  defp request_body(example, drop_id: true) do
    body = Map.delete(example, "id")

    %{
      "required" => true,
      "content" => %{
        "application/json" => %{"schema" => %{"type" => "object"}, "example" => body}
      }
    }
  end

  # A PATCH example that changes everything is a poor illustration of a partial
  # update, so only the first non-id field is shown.
  defp patch_example(nil), do: nil

  defp patch_example(example) do
    case example |> Map.delete("id") |> Enum.take(1) do
      [{key, value}] -> %{key => value}
      [] -> example
    end
  end

  defp json_response(description, schema, example) do
    json = %{"schema" => schema}
    json = if is_nil(example), do: json, else: Map.put(json, "example", example)

    content =
      if System.get_env("LEYWN_ONLY_JSON") == "true" do
        %{"application/json" => json}
      else
        %{"application/json" => json, "application/xml" => %{"schema" => schema}}
      end

    %{"description" => description, "content" => content}
  end

  defp error_response(description) do
    json_response(
      description,
      %{
        "type" => "object",
        "properties" => %{"error" => %{"type" => "string"}},
        "required" => ["error"]
      },
      nil
    )
  end

  # ---------------------------------------------------------------------------
  # Schema inference
  # ---------------------------------------------------------------------------

  defp schemas(mock) do
    collections =
      for name <- mock.collection_names, into: %{} do
        {schema_name(name), infer_object(sample(mock, name))}
      end

    for name <- mock.singleton_names, into: collections do
      {schema_name(name), infer_object([Map.fetch!(mock.singletons, name)])}
    end
  end

  defp ref(name), do: %{"$ref" => "#/components/schemas/#{schema_name(name)}"}

  # Element names in the generated XML — and $ref targets here — have to be
  # legal identifiers, and collection names may contain characters that are
  # legal in a JSON key but not in either.
  defp schema_name(collection) do
    collection
    |> singular()
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.split("_", trim: true)
    |> Enum.map_join(&String.capitalize/1)
    |> case do
      "" -> "Record"
      name -> name
    end
  end

  # Properties are the union over the sample, not just the first record: a
  # field that only some records carry is still part of the shape.
  defp infer_object(records) do
    properties =
      records
      |> Enum.reduce(%{}, fn record, acc ->
        Enum.reduce(record, acc, fn {key, value}, inner ->
          case Map.get(inner, key) do
            nil -> Map.put(inner, key, infer(value))
            %{"type" => "null"} -> Map.put(inner, key, infer(value))
            existing -> Map.put(inner, key, existing)
          end
        end)
      end)

    required =
      case records do
        [] ->
          []

        _ ->
          records
          |> Enum.map(&MapSet.new(Map.keys(&1)))
          |> Enum.reduce(&MapSet.intersection/2)
          |> Enum.sort()
      end

    schema = %{"type" => "object", "properties" => properties}
    if required == [], do: schema, else: Map.put(schema, "required", required)
  end

  defp infer(value) when is_binary(value), do: %{"type" => "string"}
  defp infer(value) when is_boolean(value), do: %{"type" => "boolean"}
  defp infer(value) when is_integer(value), do: %{"type" => "integer"}
  defp infer(value) when is_float(value), do: %{"type" => "number"}
  defp infer(nil), do: %{"type" => "null"}

  defp infer(value) when is_list(value) do
    case value do
      [first | _] -> %{"type" => "array", "items" => infer(first)}
      [] -> %{"type" => "array", "items" => %{}}
    end
  end

  defp infer(value) when is_map(value), do: infer_object([value])

  # ---------------------------------------------------------------------------
  # Sampling
  # ---------------------------------------------------------------------------

  defp sample(mock, name) do
    mock.collections |> Map.fetch!(name) |> Map.fetch!(:records) |> Enum.take(@sample_size)
  end

  defp sample_record(mock, name) do
    case sample(mock, name) do
      [first | _] -> first
      [] -> nil
    end
  end

  defp field_names(mock, name) do
    mock
    |> sample(name)
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == "id"))
    |> Enum.sort()
  end

  defp singular(collection), do: Leywn.Mock.Inflect.singular(collection)
end
