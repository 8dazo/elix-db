defmodule ElixDb.Dazo.PredicateMaskTest do
  use ExUnit.Case, async: true

  alias ElixDb.Dazo.PredicateMask, as: PM

  @config [
    {"status", 0, ["active", "pending"]},
    {:category, 1, ["Electronics", "Books"]},
    {"region", 2, ["USA", "EU"]}
  ]

  describe "payload_to_mask/2" do
    test "nil payload returns 0" do
      assert PM.payload_to_mask(nil, @config) == 0
    end

    test "empty payload returns 0" do
      assert PM.payload_to_mask(%{}, @config) == 0
    end

    test "sets bit when payload key value is in allowed values" do
      assert PM.payload_to_mask(%{"status" => "active"}, @config) == 1
      assert PM.payload_to_mask(%{status: "pending"}, @config) == 1
      assert PM.payload_to_mask(%{"category" => "Electronics"}, @config) == 2
      assert PM.payload_to_mask(%{region: "USA"}, @config) == 4
    end

    test "combines multiple bits" do
      assert PM.payload_to_mask(%{"status" => "active", "category" => "Books", "region" => "EU"}, @config) == 1 + 2 + 4
    end

    test "unknown key or value not in set does not set bit" do
      assert PM.payload_to_mask(%{"status" => "archived"}, @config) == 0
      assert PM.payload_to_mask(%{"other" => "x"}, @config) == 0
    end

    test "string and atom keys both work" do
      assert PM.payload_to_mask(%{"status" => "active"}, @config) == PM.payload_to_mask(%{status: "active"}, @config)
    end
  end

  describe "filter_to_mask/2" do
    test "nil or empty filter returns 0 (no predicate pruning)" do
      assert PM.filter_to_mask(nil, @config) == 0
      assert PM.filter_to_mask(%{}, @config) == 0
    end

    test "sets bit when filter key value is in allowed values" do
      assert PM.filter_to_mask(%{"status" => "active"}, @config) == 1
      assert PM.filter_to_mask(%{category: "Books"}, @config) == 2
    end

    test "combines bits for multiple filter keys" do
      assert PM.filter_to_mask(%{status: "active", region: "USA"}, @config) == 1 + 4
    end

    test "filter key not in config does not set bit" do
      assert PM.filter_to_mask(%{"other" => "x"}, @config) == 0
    end
  end

  describe "edge_matches?/2" do
    test "query_mask 0 follows all edges" do
      assert PM.edge_matches?(0, 0) == true
      assert PM.edge_matches?(255, 0) == true
    end

    test "edge must have all bits that query requires" do
      assert PM.edge_matches?(1, 1) == true
      assert PM.edge_matches?(3, 1) == true
      assert PM.edge_matches?(0, 1) == false
      assert PM.edge_matches?(2, 1) == false
      assert PM.edge_matches?(7, 5) == true
      assert PM.edge_matches?(4, 5) == false
    end
  end

  describe "validate_config/1" do
    test "valid config returns :ok" do
      assert PM.validate_config(@config) == :ok
      assert PM.validate_config([]) == :ok
    end

    test "non-list returns error" do
      assert PM.validate_config(%{}) == {:error, :config_not_list}
    end

    test "more than 8 fields returns error" do
      config = for i <- 0..7, do: {"k#{i}", i, ["v"]}
      assert PM.validate_config(config) == :ok
      assert PM.validate_config(config ++ [{"k9", 0, ["v"]}]) == {:error, :too_many_fields}
    end

    test "bit out of range returns error" do
      assert PM.validate_config([{"k", 8, ["v"]}]) == {:error, :bit_out_of_range}
      assert PM.validate_config([{"k", -1, ["v"]}]) == {:error, :bit_out_of_range}
    end

    test "duplicate bit returns error" do
      assert PM.validate_config([{"a", 0, []}, {"b", 0, []}]) == {:error, :duplicate_bit}
    end
  end
end
