defmodule Leywn.Shape do
  @moduledoc """
  Structural limits for caller-supplied data.

  A byte cap does not bound what a payload costs once it is parsed: a 64 KiB
  body of `[[[[…]]]]` is 32 000 levels deep, and pretty-printing it indents
  every level, producing output quadratic in the input. Anything that parses
  caller data and then re-emits it checks its depth here first.
  """

  @doc "True if `term` (a decoded JSON-like structure) nests deeper than `max` levels."
  def deeper_than?(term, max) when is_integer(max) and max >= 0, do: exceeds?(term, max)

  defp exceeds?(v, 0) when is_map(v) or is_list(v), do: true
  defp exceeds?(v, max) when is_map(v), do: Enum.any?(Map.values(v), &exceeds?(&1, max - 1))
  defp exceeds?(v, max) when is_list(v), do: Enum.any?(v, &exceeds?(&1, max - 1))
  defp exceeds?(_, _), do: false
end
