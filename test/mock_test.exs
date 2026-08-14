defmodule Leywn.MockTest do
  # Not async: these tests share the overlay store, the rate-limit counters and
  # the LEYWN_MOCK_* environment, all of which are process-global.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias Leywn.Mock.{Loader, RateLimit, Store}

  @opts Leywn.Router.init([])

  setup do
    Store.reset()
    RateLimit.reset()
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp request(method, path, body \\ nil, headers \\ []) do
    method
    |> conn(path, body)
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)
    end)
    |> Leywn.Router.call(@opts)
  end

  defp get_json(path, headers \\ []) do
    conn = request(:get, path, nil, headers)
    {conn, Jason.decode!(conn.resp_body)}
  end

  defp post_json(path, map) do
    conn = request(:post, path, Jason.encode!(map), [{"content-type", "application/json"}])
    {conn, Jason.decode!(conn.resp_body)}
  end

  defp send_json(method, path, map) do
    conn = request(method, path, Jason.encode!(map), [{"content-type", "application/json"}])
    {conn, Jason.decode!(conn.resp_body)}
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  # Restores the variable afterwards so one test's configuration cannot leak
  # into the next — these all read the environment live, by design.
  defp with_env(var, value, fun) do
    previous = System.get_env(var)
    System.put_env(var, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(var, previous), else: System.delete_env(var)
    end
  end

  # ---------------------------------------------------------------------------
  # Loading
  # ---------------------------------------------------------------------------

  describe "loader" do
    test "the built-in marketplace mock is loaded at startup" do
      assert "marketplace" in Loader.names()
      assert {:ok, mock} = Loader.fetch("marketplace")
      assert mock.collection_names == ["orders", "users"]
      assert Path.basename(mock.file) == "db.json"
    end

    test "collections are indexed by id and keep their file order" do
      {:ok, mock} = Loader.fetch("marketplace")
      users = mock.collections["users"]

      assert length(users.records) == 10
      assert hd(users.records)["id"] == "a1b2c3d4"
      assert users.index["a1b2c3d4"]["fullName"] == "Alice Johnson"
      assert users.id_type == :string
    end

    test "names that could escape the mocks directory are rejected" do
      refute Loader.valid_name?("..")
      refute Loader.valid_name?("../etc")
      refute Loader.valid_name?("a/b")
      refute Loader.valid_name?(".hidden")
      refute Loader.valid_name?("")
      refute Loader.valid_name?(String.duplicate("a", 65))
      assert Loader.valid_name?("marketplace")
      assert Loader.valid_name?("my-mock_2")
    end

    test "fetching an unknown or malformed name never reaches the filesystem" do
      assert Loader.fetch("nope") == :error
      assert Loader.fetch("../../etc/passwd") == :error
      assert Loader.fetch(nil) == :error
    end

    test "integer and string ids share one index key" do
      assert Loader.id_key(1) == "1"
      assert Loader.id_key("1") == "1"
    end

    test "all three bundled mocks are loaded" do
      names = Loader.names()

      for name <- ~w(accommodations flightbooking marketplace) do
        assert name in names
      end
    end

    test "the two vacation mocks line up on airport codes" do
      {:ok, accommodations} = Loader.fetch("accommodations")
      {:ok, flights} = Loader.fetch("flightbooking")

      airports = flights.collections["airports"].records |> MapSet.new(& &1["id"])

      destination_airports =
        accommodations.collections["destinations"].records |> Enum.map(& &1["airportCode"])

      assert destination_airports != []

      for code <- destination_airports do
        assert MapSet.member?(airports, code),
               "destination airport #{code} has no matching airport in flightbooking"
      end
    end
  end

  describe "singularisation" do
    alias Leywn.Mock.Inflect

    test "regular plurals drop the s" do
      assert Inflect.singular("users") == "user"
      assert Inflect.singular("flights") == "flight"
      assert Inflect.singular("bookings") == "booking"
    end

    test "-ies becomes -y" do
      assert Inflect.singular("properties") == "property"
      assert Inflect.singular("categories") == "category"
    end

    test "-es is dropped after a sibilant" do
      assert Inflect.singular("addresses") == "address"
      assert Inflect.singular("matches") == "match"
      assert Inflect.singular("boxes") == "box"
    end

    test "words that merely end in s are left alone" do
      assert Inflect.singular("status") == "status"
      assert Inflect.singular("address") == "address"
      assert Inflect.singular("availability") == "availability"
    end

    test "foreign key candidates cover both the derived and the naive form" do
      keys = Inflect.foreign_keys("properties")

      assert "propertyId" in keys
      assert "propertieId" in keys
    end
  end

  # ---------------------------------------------------------------------------
  # Discovery
  # ---------------------------------------------------------------------------

  describe "discovery" do
    test "GET /mocks lists every loaded mock with its links" do
      {conn, body} = get_json("/mocks")
      assert conn.status == 200
      assert body["count"] >= 1

      marketplace = Enum.find(body["mocks"], &(&1["name"] == "marketplace"))
      assert marketplace["url"] == "/mocks/marketplace"
      assert marketplace["openapi_url"] == "/mocks/marketplace/openapi.json"
      assert marketplace["docs_url"] == "/docs/mocks/marketplace"
      assert "users" in marketplace["collections"]
    end

    test "GET /mocks/{mock} describes collections, counts and the write limits" do
      {conn, body} = get_json("/mocks/marketplace")
      assert conn.status == 200
      assert body["mock"] == "marketplace"
      assert body["source_file"] == "db.json"

      users = Enum.find(body["collections"], &(&1["name"] == "users"))
      assert users["records"] == 10

      assert body["writes"]["enabled"] == true
      assert body["writes"]["entries_used"] == 0
      assert is_integer(body["writes"]["entry_ttl_seconds"])
    end

    test "an unknown mock is a 404, not a crash" do
      {conn, body} = get_json("/mocks/does-not-exist")
      assert conn.status == 404
      assert body["error"] == "mock_not_found"
    end

    test "a path traversal attempt resolves to no mock" do
      conn = request(:get, "/mocks/..%2F..%2Fetc/passwd")
      assert conn.status == 404
    end

    test "a path deeper than the routes go is a 404" do
      {conn, body} = get_json("/mocks/marketplace/users/a1b2c3d4/orders/extra")
      assert conn.status == 404
      assert body["error"] == "mock_path_not_found"
    end

    test "POST /mocks is not allowed" do
      conn = request(:post, "/mocks", "")
      assert conn.status == 405
      assert header(conn, "allow") == "GET"
    end
  end

  # ---------------------------------------------------------------------------
  # Reading
  # ---------------------------------------------------------------------------

  describe "reading collections" do
    test "a collection returns its records" do
      {conn, records} = get_json("/mocks/marketplace/users")
      assert conn.status == 200
      assert length(records) == 10
      assert hd(records)["fullName"] == "Alice Johnson"
    end

    test "an unknown collection is a 404" do
      {conn, body} = get_json("/mocks/marketplace/nope")
      assert conn.status == 404
      assert body["error"] == "collection_not_found"
    end

    test "results are paged and the unpaged total is in a header" do
      {conn, records} = get_json("/mocks/marketplace/orders?_limit=5&_page=2")
      assert conn.status == 200
      assert length(records) == 5
      assert header(conn, "x-total-count") == "27"
      assert header(conn, "x-page") == "2"
      assert header(conn, "x-page-size") == "5"
      assert header(conn, "x-total-pages") == "6"
      assert hd(records)["id"] == "ord006"
    end

    test "the paging headers are exposed to browsers" do
      {conn, _} = get_json("/mocks/marketplace/users")
      assert header(conn, "access-control-expose-headers") =~ "x-total-count"
    end

    test "a page past the end is empty rather than an error" do
      {conn, records} = get_json("/mocks/marketplace/users?_page=99")
      assert conn.status == 200
      assert records == []
    end

    test "a limit above the maximum is rejected rather than silently truncated" do
      {conn, body} = get_json("/mocks/marketplace/users?_limit=100000")
      assert conn.status == 400
      assert body["error"] == "limit_too_large"
      assert body["maximum"] == 200
    end

    test "non-numeric and non-positive paging parameters are rejected" do
      assert {%{status: 400}, %{"error" => "invalid_page"}} =
               get_json("/mocks/marketplace/users?_page=abc")

      assert {%{status: 400}, %{"error" => "invalid_limit"}} =
               get_json("/mocks/marketplace/users?_limit=0")

      assert {%{status: 400}, %{"error" => "invalid_page"}} =
               get_json("/mocks/marketplace/users?_page=-1")
    end

    test "records can be sorted in both directions" do
      {_, ascending} = get_json("/mocks/marketplace/users?_sort=fullName")
      {_, descending} = get_json("/mocks/marketplace/users?_sort=fullName&_order=desc")

      assert hd(ascending)["fullName"] == "Alice Johnson"
      assert hd(descending)["fullName"] == "Julia Turner"
      assert Enum.reverse(ascending) == descending
    end

    test "an unknown sort direction is rejected" do
      {conn, body} = get_json("/mocks/marketplace/users?_sort=fullName&_order=sideways")
      assert conn.status == 400
      assert body["error"] == "invalid_order"
    end

    test "sorting on a field no record has does not crash" do
      {conn, records} = get_json("/mocks/marketplace/users?_sort=nonexistent")
      assert conn.status == 200
      assert length(records) == 10
    end

    test "any other query parameter filters on that field" do
      {conn, records} = get_json("/mocks/marketplace/orders?userId=e5f6g7h8")
      assert conn.status == 200
      assert length(records) == 3
      assert Enum.all?(records, &(&1["userId"] == "e5f6g7h8"))
    end

    test "filters combine, and a filter matching nothing yields an empty list" do
      {_, records} = get_json("/mocks/marketplace/orders?userId=e5f6g7h8&name=Salt%20(25kg)")
      assert length(records) == 1

      {conn, none} = get_json("/mocks/marketplace/orders?userId=nobody")
      assert conn.status == 200
      assert none == []
    end

    test "more filters than the configured maximum are rejected" do
      query = 1..11 |> Enum.map_join("&", &"field#{&1}=x")
      {conn, body} = get_json("/mocks/marketplace/orders?#{query}")
      assert conn.status == 400
      assert body["error"] == "too_many_filters"
    end
  end

  describe "comparison filters" do
    test "_gte and _lte bound a numeric field" do
      {conn, records} =
        get_json("/mocks/accommodations/properties?maxGuests_gte=10&maxGuests_lte=11")

      assert conn.status == 200
      assert records != []
      assert Enum.all?(records, &(&1["maxGuests"] >= 10 and &1["maxGuests"] <= 11))
    end

    test "_gt and _lt exclude the boundary" do
      {_, inclusive} = get_json("/mocks/accommodations/properties?maxGuests_gte=12")
      {_, exclusive} = get_json("/mocks/accommodations/properties?maxGuests_gt=12")

      assert inclusive != []
      assert exclusive == []
    end

    test "numbers compare numerically, not as text" do
      # "9" > "12" as strings; the filter must not agree.
      {_, records} = get_json("/mocks/accommodations/properties?maxGuests_gte=9")
      guests = Enum.map(records, & &1["maxGuests"])

      assert 12 in guests
      refute 8 in guests
    end

    test "ISO-8601 dates compare as ranges" do
      {conn, records} =
        get_json("/mocks/accommodations/availability?from_gte=2026-10-01&from_lte=2026-10-14")

      assert conn.status == 200
      assert records != []
      assert Enum.all?(records, &(&1["from"] >= "2026-10-01" and &1["from"] <= "2026-10-14"))
    end

    test "_ne excludes matching records" do
      {_, records} = get_json("/mocks/accommodations/properties?type_ne=villa&_limit=200")

      assert records != []
      refute Enum.any?(records, &(&1["type"] == "villa"))
    end

    test "_like is a case-insensitive substring, never a regex" do
      {_, records} = get_json("/mocks/accommodations/properties?name_like=VILLA")
      assert length(records) == 2

      # A regex metacharacter is matched literally rather than compiled.
      {conn, none} = get_json("/mocks/accommodations/properties?name_like=.%2A")
      assert conn.status == 200
      assert none == []
    end

    test "_like reaches into a list field" do
      {_, records} = get_json("/mocks/accommodations/properties?amenities_like=ski_storage")

      assert records != []
      assert Enum.all?(records, &("ski_storage" in &1["amenities"]))
    end

    test "a comparison against a missing field matches nothing" do
      {conn, records} = get_json("/mocks/accommodations/properties?nonexistent_gte=1")
      assert conn.status == 200
      assert records == []
    end

    test "filters combine with paging and sorting" do
      {conn, records} =
        get_json(
          "/mocks/accommodations/properties?maxGuests_gte=8&_sort=pricePerNightEur&_order=desc&_limit=2"
        )

      assert conn.status == 200
      assert length(records) == 2
      assert header(conn, "x-total-count") |> String.to_integer() > 2

      prices = Enum.map(records, & &1["pricePerNightEur"])
      assert prices == Enum.sort(prices, :desc)
    end
  end

  describe "full-text search" do
    test "q matches any scalar field of a record" do
      {conn, records} = get_json("/mocks/accommodations/properties?q=barceloneta")

      assert conn.status == 200
      assert length(records) == 1
      assert hd(records)["name"] == "Barceloneta Beach House"
    end

    test "q reaches into list fields" do
      {_, records} = get_json("/mocks/accommodations/properties?q=ski_storage")

      assert records != []
      assert Enum.all?(records, &("ski_storage" in &1["amenities"]))
    end

    test "q is case-insensitive and combines with other filters" do
      {_, records} = get_json("/mocks/accommodations/properties?q=INNSBRUCK&type=hotel")

      assert length(records) == 1
      assert hd(records)["name"] == "Igls Panorama Hotel"
    end

    test "an empty q does not filter anything out" do
      {_, all} = get_json("/mocks/accommodations/destinations")
      {_, searched} = get_json("/mocks/accommodations/destinations?q=")

      assert length(searched) == length(all)
    end

    test "an over-long search term is rejected" do
      needle = String.duplicate("a", 200)
      {conn, body} = get_json("/mocks/accommodations/properties?q=#{needle}")

      assert conn.status == 400
      assert body["error"] == "search_too_long"
    end

    test "q counts against the filter budget" do
      query = 1..10 |> Enum.map_join("&", &"field#{&1}=x")
      {conn, body} = get_json("/mocks/accommodations/properties?q=x&#{query}")

      assert conn.status == 400
      assert body["error"] == "too_many_filters"
      assert body["provided"] == 11
    end
  end

  describe "reading single records" do
    test "a record is addressable by id" do
      {conn, record} = get_json("/mocks/marketplace/users/a1b2c3d4")
      assert conn.status == 200
      assert record["fullName"] == "Alice Johnson"
    end

    test "an unknown id is a 404" do
      {conn, body} = get_json("/mocks/marketplace/users/nope")
      assert conn.status == 404
      assert body["error"] == "record_not_found"
    end

    test "a nested route follows the foreign key between two collections" do
      {conn, orders} = get_json("/mocks/marketplace/users/a1b2c3d4/orders")
      assert conn.status == 200
      assert length(orders) == 3
      assert Enum.all?(orders, &(&1["userId"] == "a1b2c3d4"))
    end

    test "a nested route on an unknown parent id is a 404" do
      {conn, body} = get_json("/mocks/marketplace/users/nope/orders")
      assert conn.status == 404
      assert body["error"] == "record_not_found"
    end

    test "a nested route with no foreign key between the collections is a 404" do
      {conn, body} = get_json("/mocks/marketplace/orders/ord001/users")
      assert conn.status == 404
      assert body["error"] == "relation_not_found"
    end

    # "properties" only reaches "propertyId" if it singularises correctly; the
    # naive "strip the s" rule yields "propertie" and the relation vanishes.
    test "an irregular plural still resolves its foreign key" do
      {conn, records} =
        get_json("/mocks/accommodations/properties/prop-gothic-loft/availability")

      assert conn.status == 200
      assert length(records) == 8
      assert Enum.all?(records, &(&1["propertyId"] == "prop-gothic-loft"))
    end

    test "nested results are filtered, sorted and paged like any collection" do
      {conn, records} =
        get_json(
          "/mocks/accommodations/properties/prop-gothic-loft/availability" <>
            "?available=true&_sort=from&_limit=3"
        )

      assert conn.status == 200
      assert length(records) == 3
      assert Enum.all?(records, & &1["available"])

      total = header(conn, "x-total-count") |> String.to_integer()
      assert total > 3 and total < 8

      froms = Enum.map(records, & &1["from"])
      assert froms == Enum.sort(froms)
    end

    test "an invalid parameter on a nested route is reported, not ignored" do
      {conn, body} =
        get_json("/mocks/accommodations/properties/prop-gothic-loft/availability?_limit=0")

      assert conn.status == 400
      assert body["error"] == "invalid_limit"
    end
  end

  describe "content negotiation" do
    test "a collection is served as XML when asked for" do
      conn =
        request(:get, "/mocks/marketplace/users?_limit=1", nil, [{"accept", "application/xml"}])

      assert conn.status == 200
      assert header(conn, "content-type") =~ "application/xml"
      assert conn.resp_body =~ "<users>"
      assert conn.resp_body =~ "<fullName>Alice Johnson</fullName>"
    end

    test "a single record uses the singular form as its XML root" do
      conn =
        request(:get, "/mocks/marketplace/users/a1b2c3d4", nil, [{"accept", "application/xml"}])

      assert conn.resp_body =~ "<user>"
    end

    test "LEYWN_ONLY_JSON overrides the Accept header" do
      with_env("LEYWN_ONLY_JSON", "true", fn ->
        conn =
          request(:get, "/mocks/marketplace/users", nil, [{"accept", "application/xml"}])

        assert header(conn, "content-type") =~ "application/json"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Writing
  # ---------------------------------------------------------------------------

  describe "creating records" do
    test "POST creates a record, returns it with a generated id and a Location" do
      {conn, record} = post_json("/mocks/marketplace/orders", %{name: "Rice", userId: "a1b2c3d4"})

      assert conn.status == 201
      assert record["name"] == "Rice"
      assert is_binary(record["id"])
      assert header(conn, "location") == "/mocks/marketplace/orders/#{record["id"]}"
    end

    test "a created record is readable and appears in its collection" do
      {_, created} = post_json("/mocks/marketplace/orders", %{name: "Rice", userId: "a1b2c3d4"})

      {conn, fetched} = get_json("/mocks/marketplace/orders/#{created["id"]}")
      assert conn.status == 200
      assert fetched["name"] == "Rice"

      {list_conn, _} = get_json("/mocks/marketplace/orders")
      assert header(list_conn, "x-total-count") == "28"
    end

    test "a created record is picked up by filters and nested routes" do
      post_json("/mocks/marketplace/orders", %{name: "Rice", userId: "a1b2c3d4"})

      {_, filtered} = get_json("/mocks/marketplace/orders?userId=a1b2c3d4")
      assert length(filtered) == 4

      {_, nested} = get_json("/mocks/marketplace/users/a1b2c3d4/orders")
      assert length(nested) == 4
    end

    test "a body may supply its own id" do
      {conn, record} = post_json("/mocks/marketplace/orders", %{id: "ord999", name: "Rice"})
      assert conn.status == 201
      assert record["id"] == "ord999"

      {fetch_conn, _} = get_json("/mocks/marketplace/orders/ord999")
      assert fetch_conn.status == 200
    end

    test "an id that already exists is a conflict" do
      {conn, body} = post_json("/mocks/marketplace/orders", %{id: "ord001", name: "Rice"})
      assert conn.status == 409
      assert body["error"] == "id_conflict"
    end

    test "an id that is not a scalar is rejected" do
      {conn, body} = post_json("/mocks/marketplace/orders", %{id: %{a: 1}, name: "Rice"})
      assert conn.status == 422
      assert body["error"] == "invalid_id"
    end

    test "generated ids continue an integer sequence where the file uses one" do
      {:ok, mock} = Loader.fetch("marketplace")
      integer_collection = %{mock.collections["users"] | id_type: :integer, max_int_id: 7}
      mock = %{mock | collections: %{"users" => integer_collection}}

      assert Leywn.Mock.Data.next_id(mock, "users", fn _ -> false end) == 8
    end

    test "creating in an unknown collection is a 404" do
      {conn, body} = post_json("/mocks/marketplace/nope", %{name: "Rice"})
      assert conn.status == 404
      assert body["error"] == "collection_not_found"
    end
  end

  describe "updating and deleting records" do
    test "PUT replaces a record but keeps the id from the path" do
      {conn, record} =
        send_json(:put, "/mocks/marketplace/users/a1b2c3d4", %{fullName: "Alice J."})

      assert conn.status == 200
      assert record == %{"id" => "a1b2c3d4", "fullName" => "Alice J."}

      {_, fetched} = get_json("/mocks/marketplace/users/a1b2c3d4")
      assert fetched["fullName"] == "Alice J."
    end

    test "PUT ignores an id in the body rather than moving the record" do
      {_, record} =
        send_json(:put, "/mocks/marketplace/users/a1b2c3d4", %{id: "hijacked", fullName: "A"})

      assert record["id"] == "a1b2c3d4"

      {conn, _} = get_json("/mocks/marketplace/users/hijacked")
      assert conn.status == 404
    end

    test "PATCH merges into the existing record" do
      {conn, record} =
        send_json(:patch, "/mocks/marketplace/orders/ord001", %{name: "Sugar 100kg"})

      assert conn.status == 200
      assert record["name"] == "Sugar 100kg"
      assert record["userId"] == "a1b2c3d4"
    end

    test "PUT and PATCH on an unknown id are 404s" do
      assert {%{status: 404}, _} = send_json(:put, "/mocks/marketplace/users/nope", %{a: 1})
      assert {%{status: 404}, _} = send_json(:patch, "/mocks/marketplace/users/nope", %{a: 1})
    end

    test "DELETE removes the record and returns what was removed" do
      {conn, record} = get_json("/mocks/marketplace/orders/ord002")
      assert conn.status == 200

      deleted_conn = request(:delete, "/mocks/marketplace/orders/ord002")
      assert deleted_conn.status == 200
      assert Jason.decode!(deleted_conn.resp_body) == record

      {after_conn, body} = get_json("/mocks/marketplace/orders/ord002")
      assert after_conn.status == 404
      assert body["error"] == "record_not_found"

      {list_conn, _} = get_json("/mocks/marketplace/orders")
      assert header(list_conn, "x-total-count") == "26"
    end

    test "DELETE of an unknown id is a 404" do
      conn = request(:delete, "/mocks/marketplace/orders/nope")
      assert conn.status == 404
    end

    test "a record created and then deleted disappears entirely" do
      {_, created} = post_json("/mocks/marketplace/orders", %{name: "Rice"})
      request(:delete, "/mocks/marketplace/orders/#{created["id"]}")

      {conn, _} = get_json("/mocks/marketplace/orders/#{created["id"]}")
      assert conn.status == 404

      {list_conn, _} = get_json("/mocks/marketplace/orders")
      assert header(list_conn, "x-total-count") == "27"
    end
  end

  # ---------------------------------------------------------------------------
  # Body validation
  # ---------------------------------------------------------------------------

  describe "rejecting bad bodies" do
    test "a body that is not JSON is rejected" do
      conn = request(:post, "/mocks/marketplace/orders", "not json")
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "invalid_json"
    end

    test "a body that is not a JSON object is rejected" do
      conn = request(:post, "/mocks/marketplace/orders", "[1, 2, 3]")
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "invalid_body"
    end

    test "a body over the size limit is rejected before it is parsed" do
      oversized = Jason.encode!(%{name: String.duplicate("x", 20_000)})
      conn = request(:post, "/mocks/marketplace/orders", oversized)

      assert conn.status == 413
      assert Jason.decode!(conn.resp_body)["error"] == "payload_too_large"
    end

    test "a deeply nested body is rejected even when it is small" do
      nested = Enum.reduce(1..30, %{"a" => 1}, fn _, acc -> %{"n" => acc} end)
      {conn, body} = post_json("/mocks/marketplace/orders", nested)

      assert byte_size(Jason.encode!(nested)) < 16_384
      assert conn.status == 422
      assert body["error"] == "body_too_deep"
    end

    test "an object with more keys than allowed is rejected" do
      wide = for i <- 1..101, into: %{}, do: {"k#{i}", 1}
      {conn, body} = post_json("/mocks/marketplace/orders", wide)

      assert conn.status == 422
      assert body["error"] == "too_many_keys"
    end

    test "nesting is measured through lists as well as objects" do
      nested = Enum.reduce(1..30, [1], fn _, acc -> [acc] end)
      conn = request(:post, "/mocks/marketplace/orders", Jason.encode!(%{"deep" => nested}))

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "body_too_deep"
    end
  end

  # ---------------------------------------------------------------------------
  # Limits
  # ---------------------------------------------------------------------------

  describe "read-only mode" do
    test "every mutating method is refused and reads still work" do
      with_env("LEYWN_MOCK_READONLY", "true", fn ->
        for {method, path} <- [
              {:post, "/mocks/marketplace/orders"},
              {:put, "/mocks/marketplace/orders/ord001"},
              {:patch, "/mocks/marketplace/orders/ord001"},
              {:delete, "/mocks/marketplace/orders/ord001"}
            ] do
          conn = request(method, path, "{}", [{"content-type", "application/json"}])

          assert conn.status == 405, "#{method} #{path} should be refused"
          assert header(conn, "allow") == "GET"
          assert Jason.decode!(conn.resp_body)["error"] == "mock_read_only"
        end

        assert {%{status: 200}, _} = get_json("/mocks/marketplace/orders/ord001")
      end)
    end

    test "read-only mode is reported on the mock overview" do
      with_env("LEYWN_MOCK_READONLY", "true", fn ->
        {_, body} = get_json("/mocks/marketplace")
        assert body["writes"]["enabled"] == false
      end)
    end
  end

  describe "rate limiting" do
    test "writes beyond the per-client budget are refused with a Retry-After" do
      with_env("LEYWN_MOCK_WRITE_RATE_LIMIT", "2", fn ->
        assert {%{status: 201}, _} = post_json("/mocks/marketplace/orders", %{name: "one"})
        assert {%{status: 201}, _} = post_json("/mocks/marketplace/orders", %{name: "two"})

        conn = request(:post, "/mocks/marketplace/orders", ~s({"name":"three"}))
        assert conn.status == 429

        body = Jason.decode!(conn.resp_body)
        assert body["error"] == "rate_limited"
        assert body["limit_per_minute"] == 2

        retry_after = header(conn, "retry-after") |> String.to_integer()
        assert retry_after >= 1 and retry_after <= 60
      end)
    end

    test "the global budget applies regardless of the client address" do
      with_env("LEYWN_MOCK_WRITE_RATE_LIMIT_GLOBAL", "1", fn ->
        assert {%{status: 201}, _} = post_json("/mocks/marketplace/orders", %{name: "one"})

        conn =
          :post
          |> conn("/mocks/marketplace/orders", ~s({"name":"two"}))
          |> Map.put(:remote_ip, {203, 0, 113, 9})
          |> Leywn.Router.call(@opts)

        assert conn.status == 429
      end)
    end

    test "reads are never rate limited" do
      with_env("LEYWN_MOCK_WRITE_RATE_LIMIT", "1", fn ->
        for _ <- 1..20 do
          assert {%{status: 200}, _} = get_json("/mocks/marketplace/users")
        end
      end)
    end

    test "a limit of zero blocks writes outright" do
      with_env("LEYWN_MOCK_WRITE_RATE_LIMIT", "0", fn ->
        conn = request(:post, "/mocks/marketplace/orders", ~s({"name":"x"}))
        assert conn.status == 429
      end)
    end
  end

  describe "storage caps" do
    test "a mock stops accepting changes once it holds its maximum" do
      with_env("LEYWN_MOCK_MAX_NEW_ENTRIES", "3", fn ->
        for i <- 1..3 do
          assert {%{status: 201}, _} =
                   post_json("/mocks/marketplace/orders", %{name: "item #{i}"})
        end

        {conn, body} = post_json("/mocks/marketplace/orders", %{name: "one too many"})
        assert conn.status == 507
        assert body["error"] == "mock_storage_full"
        assert body["max_new_entries"] == 3
      end)
    end

    test "the total byte ceiling is enforced independently of the entry count" do
      with_env("LEYWN_MOCK_MAX_OVERLAY_BYTES", "10", fn ->
        {conn, body} =
          post_json("/mocks/marketplace/orders", %{name: "a name well over ten bytes"})

        assert conn.status == 507
        assert body["error"] == "mock_storage_full"
        assert body["max_overlay_bytes"] == 10
      end)
    end

    test "updates to the same record do not consume additional slots" do
      with_env("LEYWN_MOCK_MAX_NEW_ENTRIES", "1", fn ->
        assert {%{status: 200}, _} =
                 send_json(:patch, "/mocks/marketplace/orders/ord001", %{name: "first"})

        assert {%{status: 200}, _} =
                 send_json(:patch, "/mocks/marketplace/orders/ord001", %{name: "second"})

        assert Store.count("marketplace") == 1
      end)
    end

    test "freed slots become available again" do
      with_env("LEYWN_MOCK_MAX_NEW_ENTRIES", "1", fn ->
        assert {%{status: 201}, _} = post_json("/mocks/marketplace/orders", %{name: "one"})
        assert {%{status: 507}, _} = post_json("/mocks/marketplace/orders", %{name: "two"})

        Store.reset()

        assert {%{status: 201}, _} = post_json("/mocks/marketplace/orders", %{name: "three"})
      end)
    end
  end

  describe "expiry" do
    test "a created record is forgotten once its lease runs out" do
      with_env("LEYWN_MOCK_ENTRY_TTL_SECONDS", "1", fn ->
        {_, created} = post_json("/mocks/marketplace/orders", %{name: "temporary"})

        assert {%{status: 200}, _} = get_json("/mocks/marketplace/orders/#{created["id"]}")

        Process.sleep(1_100)

        assert {%{status: 404}, _} = get_json("/mocks/marketplace/orders/#{created["id"]}")

        {list_conn, _} = get_json("/mocks/marketplace/orders")
        assert header(list_conn, "x-total-count") == "27"
      end)
    end

    test "a deletion is forgotten too, so the file record comes back" do
      with_env("LEYWN_MOCK_ENTRY_TTL_SECONDS", "1", fn ->
        assert request(:delete, "/mocks/marketplace/orders/ord001").status == 200
        assert {%{status: 404}, _} = get_json("/mocks/marketplace/orders/ord001")

        Process.sleep(1_100)

        {conn, record} = get_json("/mocks/marketplace/orders/ord001")
        assert conn.status == 200
        assert record["name"] == "Sugar (50kg)"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Generated documentation
  # ---------------------------------------------------------------------------

  describe "generated OpenAPI" do
    test "the spec covers every collection with full CRUD" do
      {conn, spec} = get_json("/mocks/marketplace/openapi.json")

      assert conn.status == 200
      assert header(conn, "content-type") =~ "application/json"
      assert spec["openapi"] == "3.0.3"
      assert spec["info"]["title"] == "Leywn mock: marketplace"

      paths = spec["paths"]
      assert Map.has_key?(paths, "/mocks/marketplace/users")
      assert Map.has_key?(paths, "/mocks/marketplace/users/{id}")

      assert Map.keys(paths["/mocks/marketplace/users"]) |> Enum.sort() == ["get", "post"]

      assert Map.keys(paths["/mocks/marketplace/users/{id}"]) |> Enum.sort() ==
               ["delete", "get", "patch", "put"]
    end

    test "schemas and examples are inferred from the data itself" do
      {_, spec} = get_json("/mocks/marketplace/openapi.json")

      user = spec["components"]["schemas"]["User"]
      assert user["type"] == "object"
      assert user["properties"]["fullName"] == %{"type" => "string"}
      assert "id" in user["required"]

      example =
        spec["paths"]["/mocks/marketplace/users/{id}"]["get"]["responses"]["200"]["content"][
          "application/json"
        ]["example"]

      assert example["fullName"] == "Alice Johnson"
    end

    test "only relations the data actually supports are documented" do
      {_, spec} = get_json("/mocks/marketplace/openapi.json")

      assert Map.has_key?(spec["paths"], "/mocks/marketplace/users/{id}/orders")
      refute Map.has_key?(spec["paths"], "/mocks/marketplace/orders/{id}/users")
    end

    test "the servers array points back at the requested origin" do
      {conn, spec} = get_json("/mocks/marketplace/openapi.json")
      assert hd(spec["servers"])["url"] == "http://#{conn.host}"
    end

    test "read-only installations do not document write operations" do
      with_env("LEYWN_MOCK_READONLY", "true", fn ->
        {_, spec} = get_json("/mocks/marketplace/openapi.json")

        assert Map.keys(spec["paths"]["/mocks/marketplace/users"]) == ["get"]
        assert Map.keys(spec["paths"]["/mocks/marketplace/users/{id}"]) == ["get"]
        assert spec["info"]["description"] =~ "read-only"
      end)
    end

    test "LEYWN_ONLY_JSON removes the XML response variants from the spec" do
      with_env("LEYWN_ONLY_JSON", "true", fn ->
        {_, spec} = get_json("/mocks/marketplace/openapi.json")

        content =
          spec["paths"]["/mocks/marketplace/users"]["get"]["responses"]["200"]["content"]

        assert Map.keys(content) == ["application/json"]
      end)
    end

    test "the spec reflects records written since startup" do
      post_json("/mocks/marketplace/orders", %{name: "Rice", userId: "a1b2c3d4"})

      {conn, _spec} = get_json("/mocks/marketplace/openapi.json")
      assert conn.status == 200
    end
  end

  describe "Swagger UI pages" do
    test "each mock has a documentation page pointed at its own spec" do
      conn = request(:get, "/docs/mocks/marketplace")

      assert conn.status == 200
      assert header(conn, "content-type") =~ "text/html"
      assert conn.resp_body =~ "Leywn mock – marketplace"
      assert conn.resp_body =~ "url: '/mocks/marketplace/openapi.json'"
      assert conn.resp_body =~ "integrity="
    end

    test "the home page links to every mock" do
      conn = request(:get, "/")

      assert conn.status == 200
      assert conn.resp_body =~ "/docs/mocks/marketplace"
      assert conn.resp_body =~ "Mock APIs"
    end

    test "the main OpenAPI documents the mock endpoints" do
      {conn, spec} = get_json("/openapi.json")

      assert conn.status == 200
      assert Map.has_key?(spec["paths"], "/mocks")
      assert Enum.any?(spec["tags"], &(&1["name"] == "Mock"))
    end

    test "a documentation page for an unknown mock is a 404" do
      conn = request(:get, "/docs/mocks/nope")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "mock_not_found"
    end
  end

  # ---------------------------------------------------------------------------
  # Store and rate limiter internals
  # ---------------------------------------------------------------------------

  describe "store" do
    test "reads see nothing until something is written" do
      assert Store.get("marketplace", "users", "a1b2c3d4") == :miss
      assert Store.overlay("marketplace", "users") == []
    end

    test "a put is visible, a delete masks, and reset clears both" do
      assert Store.put("marketplace", "users", "x1", %{"id" => "x1"}) == :ok
      assert Store.get("marketplace", "users", "x1") == {:ok, %{"id" => "x1"}}

      assert Store.delete("marketplace", "users", "x1") == :ok
      assert Store.get("marketplace", "users", "x1") == :deleted

      Store.reset()
      assert Store.get("marketplace", "users", "x1") == :miss
      assert Store.count("marketplace") == 0
    end

    test "entries of one mock are invisible to another" do
      Store.put("marketplace", "users", "x1", %{"id" => "x1"})

      assert Store.get("other", "users", "x1") == :miss
      assert Store.overlay("other", "users") == []
    end

    test "stats report what is held" do
      Store.put("marketplace", "users", "x1", %{"id" => "x1"})
      stats = Store.stats()

      assert stats.entries == 1
      assert stats.bytes > 0
    end
  end

  describe "rate limiter" do
    test "the client key follows LEYWN_TRUST_FORWARD" do
      conn = conn(:post, "/mocks") |> Map.put(:remote_ip, {198, 51, 100, 7})

      assert Leywn.Mock.RateLimit.client_key(conn) == "198.51.100.7"

      forwarded = put_req_header(conn, "x-forwarded-for", "203.0.113.5, 10.0.0.1")

      with_env("LEYWN_TRUST_FORWARD", "true", fn ->
        assert Leywn.Mock.RateLimit.client_key(forwarded) == "203.0.113.5"
      end)

      assert Leywn.Mock.RateLimit.client_key(forwarded) == "198.51.100.7"
    end

    test "a forwarded value cannot grow the key beyond a bounded size" do
      conn =
        conn(:post, "/mocks")
        |> Map.put(:remote_ip, {198, 51, 100, 7})
        |> put_req_header("x-forwarded-for", String.duplicate("a", 5_000))

      with_env("LEYWN_TRUST_FORWARD", "true", fn ->
        assert byte_size(Leywn.Mock.RateLimit.client_key(conn)) == 64
      end)
    end
  end
end
