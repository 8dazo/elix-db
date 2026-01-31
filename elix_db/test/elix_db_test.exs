defmodule ElixDbTest do
  use ExUnit.Case
  doctest ElixDb

  test "greets the world" do
    assert ElixDb.hello() == :world
  end
end
