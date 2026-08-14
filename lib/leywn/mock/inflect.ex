defmodule Leywn.Mock.Inflect do
  @moduledoc """
  Turns a collection name into its singular form.

  Three parts of the mock subsystem need this: the XML root element for a single
  record (`<user>` inside `<users>`), the schema name in a generated OpenAPI
  document, and — the one that actually matters — the foreign key a nested route
  looks for. `/properties/{id}/availability` can only work if `properties`
  singularises to `property`, because the field in the data is `propertyId`.

  Only the rules that earn their place are here. This is not an inflection
  library, and a collection whose plural it gets wrong still works: nested
  routes try several candidate keys, and both the naive and the derived forms
  are among them.
  """

  @doc """
  The singular of a collection name.

      iex> Leywn.Mock.Inflect.singular("properties")
      "property"
      iex> Leywn.Mock.Inflect.singular("addresses")
      "address"
      iex> Leywn.Mock.Inflect.singular("status")
      "status"
  """
  def singular(name) when is_binary(name) do
    cond do
      # "properties" -> "property". Guarded on length so "ties" does not become
      # "ty" and, more to the point, so a three-letter name is left alone.
      String.ends_with?(name, "ies") and String.length(name) > 4 ->
        String.replace_suffix(name, "ies", "y")

      # "addresses" -> "address", "matches" -> "match", "boxes" -> "box".
      String.ends_with?(name, ["sses", "shes", "ches", "xes", "zes"]) ->
        String.replace_suffix(name, "es", "")

      # "status" and "address" are already singular despite the trailing s;
      # stripping it would produce "statu" and hand every nested route a key
      # that exists nowhere in the data.
      String.ends_with?(name, ["ss", "us", "is", "s's"]) ->
        name

      String.ends_with?(name, "s") and String.length(name) > 1 ->
        String.replace_suffix(name, "s", "")

      true ->
        name
    end
  end

  @doc """
  Candidate foreign-key names pointing at `parent`.

  Both the derived singular and the naive one are offered, so a dataset written
  against either convention resolves.
  """
  def foreign_keys(parent) when is_binary(parent) do
    naive = String.replace_suffix(parent, "s", "")

    [singular(parent), naive, parent]
    |> Enum.uniq()
    |> Enum.flat_map(&[&1 <> "Id", &1 <> "_id"])
    |> Enum.uniq()
  end
end
