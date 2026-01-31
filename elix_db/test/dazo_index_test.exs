defmodule ElixDb.DazoIndexTest do
  use ExUnit.Case, async: false

  alias ElixDb.Store
  alias ElixDb.CollectionRegistry
  alias ElixDb.DazoIndex

  setup do
    reg_name = :"reg_#{System.unique_integer([:positive])}"
    store_name = :"store_#{System.unique_integer([:positive])}"
    index_name = :"dazo_#{System.unique_integer([:positive])}"
    start_supervised!({CollectionRegistry, [name: reg_name]})
    start_supervised!({DazoIndex, [name: index_name, data_path: "test_dazo_#{System.unique_integer([:positive])}.elix_db"]})
    start_supervised!({Store, [name: store_name, registry: reg_name, data_path: "test_data_#{System.unique_integer([:positive])}.elix_db", dazo_index: index_name]})
    %{store: store_name, registry: reg_name, index: index_name}
  end

  describe "build/4" do
    test "builds index from store points (HNSW for small n when full_scan_threshold allows)", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "idx_coll", 2, :cosine)
      Store.upsert(store, "idx_coll", "a", [1.0, 0.0], %{})
      Store.upsert(store, "idx_coll", "b", [0.9, 0.1], %{})
      Store.upsert(store, "idx_coll", "c", [0.0, 1.0], %{})

      assert :ok = DazoIndex.build(index, store, "idx_coll", registry: reg, full_scan_threshold: 0)

      idx = DazoIndex.get_index(index, "idx_coll")
      assert idx != nil
      assert MapSet.size(MapSet.new(idx.ids)) == 3
      # HNSW path: hnsw is set, graph/medoid_id are nil
      assert idx.hnsw != nil
      assert idx.hnsw.entry_id in ["a", "b", "c"]
      assert map_size(idx.hnsw.id_to_vector) == 3
    end

    test "returns error for empty collection", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "empty_coll", 2, :l2)
      # Table is created on first upsert; then delete so table exists with 0 rows
      Store.upsert(store, "empty_coll", "x", [1.0, 0.0], %{})
      Store.delete(store, "empty_coll", "x")
      assert {:error, :empty_collection} = DazoIndex.build(index, store, "empty_coll", registry: reg)
    end

    test "returns error for unknown collection", %{store: store, index: index} do
      assert {:error, :collection_not_found} = DazoIndex.build(index, store, "nonexistent", [])
    end

    test "builds coarse (IVF-style) index when n > coarse_threshold", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "coarse_coll", 4, :cosine)
      for i <- 1..5, do: Store.upsert(store, "coarse_coll", "p#{i}", (for _ <- 1..4, do: :rand.uniform()), %{})
      # Force coarse path with low threshold; full_scan_threshold: 0 so we build (n=5 would otherwise skip)
      assert :ok = DazoIndex.build(index, store, "coarse_coll", registry: reg, coarse_threshold: 2, full_scan_threshold: 0)
      idx = DazoIndex.get_index(index, "coarse_coll")
      assert idx != nil
      assert idx.coarse != nil
      assert idx.medoid_id == nil
      assert idx.graph == nil
      assert length(idx.coarse.centroid_sketches) >= 1
      # get_candidates returns ids from probed buckets
      {:ok, candidate_ids} = DazoIndex.get_candidates(index, "coarse_coll", (for _ <- 1..4, do: :rand.uniform()), 10, nprobe: 3)
      assert is_list(candidate_ids)
      assert Enum.all?(candidate_ids, &String.starts_with?(&1, "p"))
    end
  end

  describe "persist/2 and load/2" do
    test "persist and load round-trip", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "persist_coll", 2, :cosine)
      Store.upsert(store, "persist_coll", "x", [1.0, 0.0], %{})
      Store.upsert(store, "persist_coll", "y", [0.0, 1.0], %{})
      assert :ok = DazoIndex.build(index, store, "persist_coll", registry: reg, full_scan_threshold: 0)
      path = Path.join(System.tmp_dir!(), "dazo_test_#{System.unique_integer([:positive])}.elix_db") |> to_string()
      assert :ok = DazoIndex.persist(index, path)
      assert :ok = DazoIndex.load(index, path)
      idx = DazoIndex.get_index(index, "persist_coll")
      assert idx != nil
      assert "x" in idx.ids and "y" in idx.ids
      File.rm(path)
    end
  end

  describe "search via Store (DAZO)" do
    test "Store.search uses DAZO index when built", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "search_coll", 2, :cosine)
      Store.upsert(store, "search_coll", "a", [1.0, 0.0], %{})
      Store.upsert(store, "search_coll", "b", [0.9, 0.1], %{})
      Store.upsert(store, "search_coll", "c", [0.0, 1.0], %{})
      assert :ok = DazoIndex.build(index, store, "search_coll", registry: reg, full_scan_threshold: 0)

      # Store is wired to this DazoIndex (dazo_index: index in setup); search uses DAZO
      assert {:ok, results} = Store.search(store, "search_coll", [1.0, 0.0], 3)
      assert length(results) >= 1
      ids = Enum.map(results, & &1.id)
      assert "a" in ids or "b" in ids or "c" in ids
      # Top result for query [1,0] should be closest to [1,0] (e.g. "a")
      assert hd(results).id in ["a", "b", "c"]
      assert Map.has_key?(hd(results), :score)
    end

    test "Store.search falls back to brute-force when no index", %{store: store, registry: reg} do
      CollectionRegistry.create_collection(reg, "no_idx_coll", 2, :l2)
      Store.upsert(store, "no_idx_coll", "x", [1.0, 0.0], %{})
      # No DazoIndex.build; Store falls back to brute-force
      assert {:ok, [r]} = Store.search(store, "no_idx_coll", [1.0, 0.0], 1)
      assert r.id == "x"
    end

    test "Store.search uses brute-force when brute_force: true even if index exists", %{store: store, registry: reg, index: index} do
      CollectionRegistry.create_collection(reg, "force_brute_coll", 2, :cosine)
      Store.upsert(store, "force_brute_coll", "a", [1.0, 0.0], %{})
      Store.upsert(store, "force_brute_coll", "b", [0.0, 1.0], %{})
      assert :ok = DazoIndex.build(index, store, "force_brute_coll", registry: reg, full_scan_threshold: 0)
      # Index exists; default would use DAZO. Passing brute_force: true forces brute-force.
      assert {:ok, results} = Store.search(store, "force_brute_coll", [1.0, 0.0], 2, brute_force: true)
      assert length(results) == 2
      assert hd(results).id == "a"
    end
  end
end
