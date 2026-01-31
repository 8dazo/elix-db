defmodule ElixDb.StressTest do
  @moduledoc """
  Stress/scale tests: 10k vectors to validate correctness and capture latency regression.
  Run with: mix test test/stress_test.exs
  Exclude in quick runs: mix test --exclude stress
  """
  use ExUnit.Case, async: false

  @stress_n 10_000
  @dim 32

  setup do
    reg_name = :"reg_stress_#{System.unique_integer([:positive])}"
    store_name = :"store_stress_#{System.unique_integer([:positive])}"
    index_name = :"dazo_stress_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg_name]})
    start_supervised!({ElixDb.DazoIndex, [name: index_name, data_path: "test_stress_dazo_#{System.unique_integer([:positive])}.elix_db"]})
    start_supervised!({ElixDb.Store, [name: store_name, registry: reg_name, dazo_index: index_name]})
    ElixDb.CollectionRegistry.create_collection(reg_name, "stress", @dim, :cosine)
    {:ok, registry: reg_name, store: store_name, index: index_name}
  end

  @tag :stress
  test "10k vectors: upsert, search correctness, and latency", %{store: store, registry: reg, index: index} do
    # Insert 10k points (batch for speed)
    batch_size = 500
    for b <- 0..(div(@stress_n, batch_size) - 1) do
      points = for i <- 1..batch_size do
        idx = b * batch_size + i
        vec = for _ <- 1..@dim, do: :rand.uniform()
        {"p#{idx}", vec, %{idx: idx}}
      end
      assert :ok = ElixDb.Store.upsert_batch(store, "stress", points)
    end

    # Build DAZO index (coarse path at 10k so build finishes in seconds)
    assert :ok = ElixDb.DazoIndex.build(index, store, "stress", registry: reg, timeout: 120_000)

    # Correctness: query with p1's vector should return p1 first (DAZO search)
    p1 = ElixDb.Store.get(store, "stress", "p1", with_vector: true)
    assert p1 != nil
    query = p1.vector

    {search_us, {:ok, results}} = :timer.tc(fn -> ElixDb.Store.search(store, "stress", query, 10) end)
    assert length(results) == 10
    [first | _] = results
    assert first.id == "p1"
    assert first.score >= 0.999, "cosine self-similarity should be ~1.0"

    # Latency: search at 10k with DAZO should complete in reasonable time (e.g. < 5s)
    search_ms = search_us / 1000
    assert search_ms < 10_000, "search at 10k vectors took #{search_ms} ms (expected < 10s)"
  end

  @tag :stress
  test "10k vectors: batch upsert and search", %{store: store, registry: reg, index: index} do
    batch_size = 500
    batches = div(@stress_n, batch_size)
    points = for b <- 0..(batches - 1), i <- 1..batch_size do
      idx = b * batch_size + i
      vec = for _ <- 1..@dim, do: :rand.uniform()
      {"p#{idx}", vec, %{idx: idx}}
    end
    assert :ok = ElixDb.Store.upsert_batch(store, "stress", points)

    # Build DAZO (coarse) so search is fast
    assert :ok = ElixDb.DazoIndex.build(index, store, "stress", registry: reg, timeout: 120_000)

    query = for _ <- 1..@dim, do: :rand.uniform()
    assert {:ok, results} = ElixDb.Store.search(store, "stress", query, 5)
    assert length(results) == 5
    assert Enum.all?(results, fn r -> r.id != nil and r.score != nil end)
  end
end
