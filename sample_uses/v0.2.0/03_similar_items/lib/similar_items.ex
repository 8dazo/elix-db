defmodule SimilarItems do
  @moduledoc """
  “Similar items”: store item vectors by id, then given one id, get its vector,
  run search, return top-k similar (excluding self).
  """

  @target_ids ~w(item_a item_b item_c item_d)

  def run do
    coll = "items"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "item_a", [1.0, 0.0, 0.0], %{name: "A"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_b", [0.9, 0.1, 0.0], %{name: "B"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_c", [0.0, 1.0, 0.0], %{name: "C"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_d", [0.0, 0.0, 1.0], %{name: "D"})

    # Find items similar to "item_a"
    target_id = "item_a"
    point = ElixDb.Store.get(ElixDb.Store, coll, target_id, with_vector: true)
    vector = point.vector
    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, vector, 4)

    # Exclude self (item_a)
    similar = Enum.reject(results, fn r -> r.id == target_id end)
    IO.puts("Items similar to #{target_id}:")
    Enum.each(similar, fn r -> IO.inspect(r, label: nil) end)
  end

  @doc """
  Runs a fixed workload: 4 item inserts, then 4 get+search (one per target id).
  Writes bench_result.json for the benchmark runner.
  """
  def run_bench do
    mem_before = :erlang.memory(:total)
    coll = "items_bench"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "item_a", [1.0, 0.0, 0.0], %{name: "A"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_b", [0.9, 0.1, 0.0], %{name: "B"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_c", [0.0, 1.0, 0.0], %{name: "C"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_d", [0.0, 0.0, 1.0], %{name: "D"})

    {wall_us, _} = :timer.tc(fn ->
      for id <- @target_ids do
        point = ElixDb.Store.get(ElixDb.Store, coll, id, with_vector: true)
        if point, do: ElixDb.Store.search(ElixDb.Store, coll, point.vector, 4)
      end
    end)

    mem_after = :erlang.memory(:total)
    result = %{
      inserts: 4,
      searches: length(@target_ids),
      wall_us: wall_us,
      memory_bytes: mem_after - mem_before
    }
    File.write!("bench_result.json", encode_bench_result(result))
    result
  end

  defp encode_bench_result(m) do
    ~s|{"inserts":#{m.inserts},"searches":#{m.searches},"wall_us":#{m.wall_us},"memory_bytes":#{m.memory_bytes}}|
  end
end
