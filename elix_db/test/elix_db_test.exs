defmodule ElixDbTest do
  use ExUnit.Case, async: true

  test "application and core modules are available" do
    assert Code.ensure_loaded?(ElixDb)
    assert Code.ensure_loaded?(ElixDb.Store)
    assert Code.ensure_loaded?(ElixDb.CollectionRegistry)
  end
end
