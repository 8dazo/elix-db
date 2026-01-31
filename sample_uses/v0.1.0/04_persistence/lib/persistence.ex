defmodule Persistence do
  @moduledoc """
  Persistence demo: create collection, upsert points, call ElixDb.Store.persist/1.
  After restart the store loads from disk and search still works.
  """

  @query_list [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.5, 0.5, 0.0]]

  def run do
    coll = "persisted"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "x", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "y", [0.0, 1.0, 0.0], %{})

    ElixDb.Store.persist(ElixDb.Store)
    IO.puts("Persisted to disk (data.elix_db).")

    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, [1.0, 0.0, 0.0], 5)
    IO.puts("Search after persist: #{length(results)} result(s).")
    Enum.each(results, fn r -> IO.inspect(r, label: nil) end)

    IO.puts("\nTo see load-after-restart: stop this process and run again;")
    IO.puts("ElixDb loads from disk on startup, so the same collection and points will be available.")
  end

  @doc """
  Runs a fixed workload: 2 inserts, persist, then 3 searches.
  Writes bench_result.json for the benchmark runner.
  """
  def run_bench do
    mem_before = :erlang.memory(:total)
    coll = "persisted_bench"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    {wall_us, _} = :timer.tc(fn ->
      ElixDb.Store.upsert(ElixDb.Store, coll, "x", [1.0, 0.0, 0.0], %{})
      ElixDb.Store.upsert(ElixDb.Store, coll, "y", [0.0, 1.0, 0.0], %{})
      ElixDb.Store.persist(ElixDb.Store)
      for q <- @query_list do
        ElixDb.Store.search(ElixDb.Store, coll, q, 5)
      end
    end)

    mem_after = :erlang.memory(:total)
    result = %{
      inserts: 2,
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
