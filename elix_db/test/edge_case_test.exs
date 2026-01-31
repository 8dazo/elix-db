defmodule ElixDb.EdgeCaseTest do
  @moduledoc """
  Edge cases and production-readiness: empty inputs, invalid payloads, zero vectors, malformed data.
  """
  use ExUnit.Case, async: false

  setup do
    reg_name = :"reg_edge_#{System.unique_integer([:positive])}"
    store_name = :"store_edge_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "coll", 2, :cosine)
    ElixDb.Store.upsert(store_name, "coll", "p1", [1.0, 0.0], %{})
    {:ok, registry: reg_name, store: store_name}
  end

  describe "Store edge cases" do
    test "get_many with empty ids returns []", %{store: store} do
      assert ElixDb.Store.get_many(store, "coll", []) == []
    end

    test "get_many on missing collection returns []", %{store: store} do
      assert ElixDb.Store.get_many(store, "nonexistent", ["id1"]) == []
    end

    test "search with k=0 returns []", %{store: store} do
      assert {:ok, []} = ElixDb.Store.search(store, "coll", [1.0, 0.0], 0)
    end

    test "upsert_batch with malformed point returns error", %{store: store} do
      # Map instead of tuple
      bad_points = [%{"id" => "x", "vector" => [1, 2], "payload" => %{}}]
      assert {:error, [_]} = ElixDb.Store.upsert_batch(store, "coll", bad_points)
    end

    test "upsert_batch with wrong vector type returns invalid_point_format", %{store: store} do
      # Tuple but vector is not list/binary
      bad_points = [{"id1", 123, %{}}]
      assert {:error, errors} = ElixDb.Store.upsert_batch(store, "coll", bad_points)
      assert Enum.any?(errors, fn {:error, {:invalid_point_format, _}} -> true; _ -> false end)
    end

    test "delete_many with empty list is ok", %{store: store} do
      assert :ok = ElixDb.Store.delete_many(store, "coll", [])
    end

    test "delete on missing collection is ok", %{store: store} do
      assert :ok = ElixDb.Store.delete(store, "nonexistent", "id")
    end
  end

  describe "Similarity edge cases" do
    test "cosine with zero-norm vector returns 0 (no crash/NaN)" do
      # Zero vector: norm = 0, avoid division by zero
      assert ElixDb.Similarity.cosine([0.0, 0.0], [1.0, 0.0]) == 0.0
      assert ElixDb.Similarity.cosine([1.0, 0.0], [0.0, 0.0]) == 0.0
      assert ElixDb.Similarity.cosine([0.0, 0.0], [0.0, 0.0]) == 0.0
    end

    test "cosine_batch with zero-norm in batch does not produce NaN" do
      query = [1.0, 0.0]
      vectors = [[1.0, 0.0], [0.0, 0.0], [0.0, 1.0]]
      result = ElixDb.Similarity.cosine_batch(query, vectors)
      assert length(result) == 3
      assert Enum.at(result, 0) >= 0.99
      assert Enum.at(result, 1) == 0.0
      assert is_number(Enum.at(result, 2))
    end
  end

  describe "CollectionRegistry edge cases" do
    test "create_collection with invalid metric returns error", %{registry: reg} do
      assert {:error, {:invalid_metric, :invalid}} =
               ElixDb.CollectionRegistry.create_collection(reg, "x", 2, :invalid)
    end

    test "create_collection dimension 0 returns error", %{registry: reg} do
      assert {:error, :invalid_dimension} =
               ElixDb.CollectionRegistry.create_collection(reg, "x", 0, :cosine)
    end

    test "delete_collection on missing collection returns not_found", %{registry: reg} do
      assert {:error, :not_found} = ElixDb.CollectionRegistry.delete_collection(reg, "nonexistent")
    end
  end
end
