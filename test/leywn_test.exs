defmodule LeywnTest do
  use ExUnit.Case

  test "application module exists" do
    assert Code.ensure_loaded?(Leywn.Router)
  end
end
