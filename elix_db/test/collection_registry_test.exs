defmodule ElixDb.CollectionRegistryTest do
  use ExUnit.Case, async: false

  setup do
    name = :"registry_#{System.unique_integer([:positive])}"
    registry = start_supervised!({ElixDb.CollectionRegistry, [name: name]})
    {:ok, registry: registry}
  end

  test "create_collection returns ok and collection", %{registry: registry} do
    assert {:ok, coll} = ElixDb.CollectionRegistry.create_collection(registry, "test", 3, :cosine)
    assert coll.name == "test"
    assert coll.dimension == 3
    assert coll.distance_metric == :cosine
  end

  test "create_collection with l2 metric", %{registry: registry} do
    assert {:ok, coll} = ElixDb.CollectionRegistry.create_collection(registry, "l2_coll", 4, :l2)
    assert coll.distance_metric == :l2
  end

  test "list_collections returns created collections", %{registry: registry} do
    assert ElixDb.CollectionRegistry.list_collections(registry) == []
    ElixDb.CollectionRegistry.create_collection(registry, "a", 2, :cosine)
    ElixDb.CollectionRegistry.create_collection(registry, "b", 2, :l2)
    list = ElixDb.CollectionRegistry.list_collections(registry)
    assert length(list) == 2
    names = Enum.map(list, & &1.name) |> Enum.sort()
    assert names == ["a", "b"]
  end

  test "get_collection returns collection or nil", %{registry: registry} do
    assert ElixDb.CollectionRegistry.get_collection(registry, "missing") == nil
    ElixDb.CollectionRegistry.create_collection(registry, "c", 5, :cosine)
    assert %ElixDb.Collection{name: "c", dimension: 5} = ElixDb.CollectionRegistry.get_collection(registry, "c")
  end

  test "delete_collection removes collection", %{registry: registry} do
    ElixDb.CollectionRegistry.create_collection(registry, "d", 2, :cosine)
    assert :ok = ElixDb.CollectionRegistry.delete_collection(registry, "d")
    assert ElixDb.CollectionRegistry.get_collection(registry, "d") == nil
    assert ElixDb.CollectionRegistry.delete_collection(registry, "d") == {:error, :not_found}
  end

  test "create_collection with duplicate name returns error", %{registry: registry} do
    ElixDb.CollectionRegistry.create_collection(registry, "dup", 2, :cosine)
    assert ElixDb.CollectionRegistry.create_collection(registry, "dup", 3, :l2) == {:error, :already_exists}
  end

  test "invalid dimension returns error", %{registry: registry} do
    assert ElixDb.CollectionRegistry.create_collection(registry, "x", 0, :cosine) == {:error, :invalid_dimension}
    assert ElixDb.CollectionRegistry.create_collection(registry, "x", -1, :cosine) == {:error, :invalid_dimension}
  end

  test "invalid metric returns error", %{registry: registry} do
    assert ElixDb.CollectionRegistry.create_collection(registry, "x", 2, :euclidean) == {:error, {:invalid_metric, :euclidean}}
  end
end
