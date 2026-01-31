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

  test "search with filter: only points matching payload are considered", %{store: store, registry: reg} do
    ElixDb.CollectionRegistry.create_collection(reg, "filter_coll", 2, :cosine)
    ElixDb.Store.upsert(store, "filter_coll", "a", [1.0, 0.0], %{status: "active"})
    ElixDb.Store.upsert(store, "filter_coll", "b", [1.0, 0.0], %{status: "archived"})
    ElixDb.Store.upsert(store, "filter_coll", "c", [0.9, 0.1], %{status: "active"})
    assert {:ok, results} = ElixDb.Store.search(store, "filter_coll", [1.0, 0.0], 5, filter: %{status: "active"})
    ids = Enum.map(results, & &1.id) |> Enum.sort()
    assert ids == ["a", "c"]
  end

  test "search with score_threshold (cosine): only scores >= threshold", %{store: store, registry: reg} do
    ElixDb.CollectionRegistry.create_collection(reg, "th_coll", 2, :cosine)
    ElixDb.Store.upsert(store, "th_coll", "p1", [1.0, 0.0], %{})
    ElixDb.Store.upsert(store, "th_coll", "p2", [0.9, 0.1], %{})
    ElixDb.Store.upsert(store, "th_coll", "p3", [0.0, 1.0], %{})
    assert {:ok, results} = ElixDb.Store.search(store, "th_coll", [1.0, 0.0], 5, score_threshold: 0.95)
    assert length(results) == 2
    assert hd(results).id == "p1"
  end

  test "search with distance_threshold (l2): only distance <= threshold", %{store: store, registry: reg} do
    ElixDb.CollectionRegistry.create_collection(reg, "l2_th", 2, :l2)
    ElixDb.Store.upsert(store, "l2_th", "a", [1.0, 0.0], %{})
    ElixDb.Store.upsert(store, "l2_th", "b", [1.0, 0.1], %{})
    ElixDb.Store.upsert(store, "l2_th", "c", [2.0, 0.0], %{})
    assert {:ok, results} = ElixDb.Store.search(store, "l2_th", [1.0, 0.0], 5, distance_threshold: 0.2)
    assert length(results) <= 2
    assert Enum.all?(results, fn r -> r.score <= 0.2 end)
  end

  test "search dot_product collection", %{store: store, registry: reg} do
    ElixDb.CollectionRegistry.create_collection(reg, "dot_coll", 3, :dot_product)
    ElixDb.Store.upsert(store, "dot_coll", "p1", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(store, "dot_coll", "p2", [0.5, 0.5, 0.0], %{})
    assert {:ok, [first | _]} = ElixDb.Store.search(store, "dot_coll", [1.0, 0.0, 0.0], 2)
    assert first.id == "p1"
    assert first.score == 1.0
  end
end
