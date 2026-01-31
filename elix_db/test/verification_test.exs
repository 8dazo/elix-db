defmodule ElixDb.VerificationTest do
  @moduledoc """
  Verification beyond small test cases: larger collections, search correctness at scale,
  and concurrent access. Use to assess production readiness.
  """
  use ExUnit.Case, async: false

  @scale_n 2_000
  @dim 32

  setup do
    reg_name = :"reg_verify_#{System.unique_integer([:positive])}"
    store_name = :"store_verify_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "scale", @dim, :cosine)
    {:ok, registry: reg_name, store: store_name}
  end

  @tag :verification
  test "upsert and search at scale (2k vectors, dim 32)", %{store: store} do
    # Insert 2k points
    for i <- 1..@scale_n do
      vec = for _ <- 1..@dim, do: :rand.uniform()
      ElixDb.Store.upsert(store, "scale", "p#{i}", vec, %{idx: i})
    end

    # Known vector: p1's vector should rank p1 first when we search with it
    p1 = ElixDb.Store.get(store, "scale", "p1", with_vector: true)
    assert p1 != nil
    query = p1.vector

    assert {:ok, results} = ElixDb.Store.search(store, "scale", query, 10)
    assert length(results) == 10
    [first | _] = results
    assert first.id == "p1"
    assert first.score >= 0.999, "cosine self-similarity should be ~1.0"
  end

  @tag :verification
  test "concurrent search (multiple readers)", %{store: store} do
    # Seed a small set
    for i <- 1..100 do
      vec = for _ <- 1..@dim, do: :rand.uniform()
      ElixDb.Store.upsert(store, "scale", "p#{i}", vec, %{})
    end

    query = for _ <- 1..@dim, do: :rand.uniform()
    tasks = for _ <- 1..20, do: Task.async(fn -> ElixDb.Store.search(store, "scale", query, 5) end)
    results = Task.await_many(tasks, 30_000)

    assert length(results) == 20
    assert Enum.all?(results, fn {:ok, list} -> length(list) <= 5 end)
  end

  @tag :verification
  test "get/delete consistency after many upserts", %{store: store} do
    n = 500
    for i <- 1..n do
      vec = List.duplicate(1.0 / @dim, @dim)
      ElixDb.Store.upsert(store, "scale", "k#{i}", vec, %{v: i})
    end

    assert %{id: "k1", payload: %{v: 1}} = ElixDb.Store.get(store, "scale", "k1")
    assert :ok = ElixDb.Store.delete_many(store, "scale", Enum.map(1..100, &"k#{&1}"))
    assert ElixDb.Store.get(store, "scale", "k1") == nil
    assert ElixDb.Store.get(store, "scale", "k101") != nil
    assert {:ok, results} = ElixDb.Store.search(store, "scale", List.duplicate(1.0 / @dim, @dim), 5)
    assert length(results) == 5
  end
end
