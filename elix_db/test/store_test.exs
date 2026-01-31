defmodule ElixDb.StoreTest do
  use ExUnit.Case, async: false

  setup do
    reg_name = :"reg_#{System.unique_integer([:positive])}"
    store_name = :"store_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "coll", 3, :cosine)
    {:ok, registry: reg_name, store: store_name}
  end

  test "upsert and get state via search later", %{registry: _reg, store: store} do
    assert :ok = ElixDb.Store.upsert(store, "coll", "p1", [1.0, 0.0, 0.0], %{x: 1})
    assert :ok = ElixDb.Store.upsert(store, "coll", "p2", [0.0, 1.0, 0.0])
    # Same id overwrites
    assert :ok = ElixDb.Store.upsert(store, "coll", "p1", [1.0, 0.0, 0.0], %{x: 2})
  end

  test "upsert collection_not_found", %{store: store} do
    assert ElixDb.Store.upsert(store, "missing", "id", [1, 2, 3]) == {:error, :collection_not_found}
  end

  test "upsert invalid_dimension", %{registry: _reg, store: store} do
    assert ElixDb.Store.upsert(store, "coll", "id", [1, 2]) == {:error, :invalid_dimension}
    assert ElixDb.Store.upsert(store, "coll", "id", [1, 2, 3, 4]) == {:error, :invalid_dimension}
  end

  test "upsert_batch", %{registry: _reg, store: store} do
    points = [
      {"b1", [1.0, 0.0, 0.0], %{a: 1}},
      {"b2", [0.0, 1.0, 0.0], %{}}
    ]
    assert :ok = ElixDb.Store.upsert_batch(store, "coll", points)
  end

  test "upsert_batch invalid dimension", %{registry: _reg, store: store} do
    points = [{"b1", [1, 2, 3], %{}}, {"b2", [1, 2], %{}}]
    assert {:error, [_]} = ElixDb.Store.upsert_batch(store, "coll", points)
  end
end
