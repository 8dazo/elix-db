defmodule ElixDb.SearchTest do
  use ExUnit.Case, async: false

  setup do
    reg_name = :"reg_#{System.unique_integer([:positive])}"
    store_name = :"store_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "cos_coll", 3, :cosine)
    ElixDb.CollectionRegistry.create_collection(reg_name, "l2_coll", 3, :l2)
    ElixDb.Store.upsert(store_name, "cos_coll", "p1", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(store_name, "cos_coll", "p2", [0.0, 1.0, 0.0], %{})
    ElixDb.Store.upsert(store_name, "cos_coll", "p3", [0.0, 0.0, 1.0], %{})
    ElixDb.Store.upsert(store_name, "l2_coll", "a", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(store_name, "l2_coll", "b", [0.0, 1.0, 0.0], %{})
    {:ok, registry: reg_name, store: store_name}
  end

  test "search cosine: query [1,0,0] returns p1 first", %{store: store} do
    assert {:ok, results} = ElixDb.Store.search(store, "cos_coll", [1.0, 0.0, 0.0], 3)
    assert length(results) == 3
    [first | _] = results
    assert first.id == "p1"
    assert first.score == 1.0
  end

  test "search cosine: k=1 returns one result", %{store: store} do
    assert {:ok, [r]} = ElixDb.Store.search(store, "cos_coll", [0.0, 1.0, 0.0], 1)
    assert r.id == "p2"
  end

  test "search l2: closest vector first", %{store: store} do
    assert {:ok, results} = ElixDb.Store.search(store, "l2_coll", [1.0, 0.0, 0.0], 2)
    assert length(results) == 2
    assert hd(results).id == "a"
    assert hd(results).score == 0.0
  end

  test "search empty collection returns []", %{store: store, registry: reg} do
    ElixDb.CollectionRegistry.create_collection(reg, "empty", 2, :cosine)
    assert {:ok, []} = ElixDb.Store.search(store, "empty", [1.0, 0.0], 5)
  end

  test "search collection_not_found", %{store: store} do
    assert ElixDb.Store.search(store, "missing", [1, 2, 3], 5) == {:error, :collection_not_found}
  end
end
