defmodule ElixDb.PropertyTest do
  @moduledoc """
  Property-based tests for elix-db. Uses StreamData and ExUnitProperties to verify
  invariants hold for arbitrary generated data (dimension, ids, vectors, payloads).
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  setup do
    reg_name = :"reg_prop_#{System.unique_integer([:positive])}"
    store_name = :"store_prop_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    {:ok, registry: reg_name, store: store_name}
  end

  property "upsert then get returns the same point (id, vector, payload)", %{registry: registry, store: store} do
    check all dim <- StreamData.integer(2..24),
              id <- StreamData.string(:alphanumeric, min_length: 1),
              vec <- StreamData.list_of(StreamData.float(), length: dim),
              payload <- StreamData.map_of(
                StreamData.string(:alphanumeric, min_length: 1),
                StreamData.one_of([StreamData.string(:alphanumeric), StreamData.integer()]),
                max_length: 4
              ) do
      coll_name = "c_" <> Integer.to_string(System.unique_integer([:positive]))
      assert {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)
      assert :ok = ElixDb.Store.upsert(store, coll_name, id, vec, payload)

      result = ElixDb.Store.get(store, coll_name, id, with_vector: true, with_payload: true)
      assert result != nil
      assert result.id == id
      assert result.payload == payload
      # Vectors may differ by float representation; compare element-wise with tolerance
      assert length(result.vector) == length(vec)
      Enum.zip(result.vector, vec) |> Enum.each(fn {a, b} -> assert abs(a - b) < 1.0e-6 end)
    end
  end

  property "search with a point's own vector returns that point first (cosine)", %{registry: registry, store: store} do
    check all dim <- StreamData.integer(2..16),
              id <- StreamData.string(:alphanumeric, min_length: 1),
              vec <- StreamData.list_of(StreamData.float(), length: dim) do
      coll_name = "c_" <> Integer.to_string(System.unique_integer([:positive]))
      assert {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)
      assert :ok = ElixDb.Store.upsert(store, coll_name, id, vec, %{})

      assert {:ok, [first | _]} = ElixDb.Store.search(store, coll_name, vec, 1)
      assert first.id == id
      assert first.score >= 0.999
    end
  end

  property "delete then get returns nil", %{registry: registry, store: store} do
    check all dim <- StreamData.integer(2..16),
              id <- StreamData.string(:alphanumeric, min_length: 1),
              vec <- StreamData.list_of(StreamData.float(), length: dim) do
      coll_name = "c_" <> Integer.to_string(System.unique_integer([:positive]))
      assert {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)
      assert :ok = ElixDb.Store.upsert(store, coll_name, id, vec, %{})
      assert ElixDb.Store.get(store, coll_name, id) != nil

      assert :ok = ElixDb.Store.delete(store, coll_name, id)
      assert ElixDb.Store.get(store, coll_name, id) == nil
    end
  end

  property "get_many returns exactly the points that exist", %{registry: registry, store: store} do
    check all dim <- StreamData.integer(2..12),
              ids <- StreamData.list_of(StreamData.string(:alphanumeric, min_length: 1), min_length: 1, max_length: 8) do
      ids = Enum.uniq(ids)
      coll_name = "c_" <> Integer.to_string(System.unique_integer([:positive]))
      assert {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)

      for {id, i} <- Enum.with_index(ids) do
        vec = List.duplicate(1.0, dim) |> List.replace_at(0, 1.0 + i * 0.1)
        ElixDb.Store.upsert(store, coll_name, id, vec, %{})
      end

      # get_many with same ids returns all
      results = ElixDb.Store.get_many(store, coll_name, ids)
      assert length(results) == length(ids)
      result_ids = Enum.map(results, & &1.id) |> Enum.sort()
      assert result_ids == Enum.sort(ids)

      # get_many with extra missing id returns only existing
      extra = ids ++ ["missing_" <> Integer.to_string(System.unique_integer([:positive]))]
      results2 = ElixDb.Store.get_many(store, coll_name, extra)
      assert length(results2) == length(ids)
    end
  end

  property "create_collection duplicate name returns already_exists", %{registry: registry} do
    check all name <- StreamData.string(:alphanumeric, min_length: 1),
              dim <- StreamData.integer(2..16) do
      name = "coll_" <> name
      assert {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, name, dim, :cosine)
      assert ElixDb.CollectionRegistry.create_collection(registry, name, dim + 1, :l2) == {:error, :already_exists}
    end
  end
end
