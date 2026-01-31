defmodule SimpleSearch do
  @moduledoc """
  Minimal “hello world” for ElixDb: create collection, upsert a few 3D points,
  run k-NN search, print results.
  """

  def run do
    coll = "demo"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "p1", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "p2", [0.0, 1.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "p3", [0.0, 0.0, 1.0], %{})

    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, [1.0, 0.0, 0.0], 5)
    IO.puts("k-NN search for [1,0,0] (top 5):")
    Enum.each(results, fn r -> IO.inspect(r, label: nil) end)
  end

  @query_list [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
    [0.5, 0.5, 0.0],
    [0.9, 0.1, 0.0]
  ]

  @doc """
  Runs a fixed workload: 3 inserts, then 5 searches from @query_list.
  Returns a map and writes bench_result.json for the benchmark runner.
  """
  def run_bench do
    mem_before = :erlang.memory(:total)
    coll = "demo_bench"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    {wall_us, _} = :timer.tc(fn ->
      ElixDb.Store.upsert(ElixDb.Store, coll, "p1", [1.0, 0.0, 0.0], %{})
      ElixDb.Store.upsert(ElixDb.Store, coll, "p2", [0.0, 1.0, 0.0], %{})
      ElixDb.Store.upsert(ElixDb.Store, coll, "p3", [0.0, 0.0, 1.0], %{})
      for q <- @query_list do
        ElixDb.Store.search(ElixDb.Store, coll, q, 5)
      end
    end)

    mem_after = :erlang.memory(:total)
    result = %{
      inserts: 3,
      searches: length(@query_list),
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
