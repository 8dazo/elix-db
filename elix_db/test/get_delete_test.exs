defmodule ElixDb.GetDeleteTest do
  use ExUnit.Case, async: false

  setup do
    reg_name = :"reg_#{System.unique_integer([:positive])}"
    store_name = :"store_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "coll", 2, :cosine)
    ElixDb.Store.upsert(store_name, "coll", "id1", [1.0, 0.0], %{status: "active"})
    ElixDb.Store.upsert(store_name, "coll", "id2", [0.0, 1.0], %{status: "archived"})
    ElixDb.Store.upsert(store_name, "coll", "id3", [1.0, 1.0], %{status: "archived"})
    {:ok, store: store_name}
  end

  test "get returns point", %{store: store} do
    assert %{id: "id1", payload: %{status: "active"}} = ElixDb.Store.get(store, "coll", "id1")
  end

  test "get returns nil for missing id", %{store: store} do
    assert ElixDb.Store.get(store, "coll", "missing") == nil
  end

  test "get_many returns multiple points", %{store: store} do
    results = ElixDb.Store.get_many(store, "coll", ["id1", "id2", "missing"])
    assert length(results) == 2
    ids = Enum.map(results, & &1.id) |> Enum.sort()
    assert ids == ["id1", "id2"]
  end

  test "delete removes point", %{store: store} do
    assert :ok = ElixDb.Store.delete(store, "coll", "id1")
    assert ElixDb.Store.get(store, "coll", "id1") == nil
    assert {:ok, results} = ElixDb.Store.search(store, "coll", [1.0, 0.0], 5)
    assert Enum.any?(results, &(&1.id == "id1")) == false
  end

  test "delete_many removes points", %{store: store} do
    assert :ok = ElixDb.Store.delete_many(store, "coll", ["id1", "id2"])
    assert ElixDb.Store.get(store, "coll", "id1") == nil
    assert ElixDb.Store.get(store, "coll", "id2") == nil
    assert ElixDb.Store.get(store, "coll", "id3") != nil
  end

  test "delete_by_filter removes matching payload", %{store: store} do
    assert :ok = ElixDb.Store.delete_by_filter(store, "coll", %{status: "archived"})
    assert ElixDb.Store.get(store, "coll", "id1") != nil
    assert ElixDb.Store.get(store, "coll", "id2") == nil
    assert ElixDb.Store.get(store, "coll", "id3") == nil
  end
end
