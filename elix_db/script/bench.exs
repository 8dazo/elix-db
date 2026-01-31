# Run: mix run script/bench.exs
# Measures insert and search latency; reports ms/op and QPS.
Application.ensure_all_started(:elix_db)

registry = ElixDb.CollectionRegistry
store = ElixDb.Store

# Create collection
ElixDb.CollectionRegistry.create_collection(registry, "bench", 64, :cosine)

# Benchmark insert
n_inserts = 1000
{t_us, _} = :timer.tc(fn ->
  for i <- 1..n_inserts do
    vec = for _ <- 1..64, do: :rand.uniform()
    ElixDb.Store.upsert(store, "bench", "p#{i}", vec, %{})
  end
end)
insert_us_per = t_us / n_inserts
insert_qps = 1_000_000 / insert_us_per

# Benchmark search
n_searches = 100
{t_search_us, _} = :timer.tc(fn ->
  for _ <- 1..n_searches do
    q = for _ <- 1..64, do: :rand.uniform()
    ElixDb.Store.search(store, "bench", q, 10)
  end
end)
search_us_per = t_search_us / n_searches
search_qps = 1_000_000 / search_us_per

report = """
# elix-db benchmark (n=#{n_inserts} vectors, dim=64, k=10)
- Insert: #{Float.round(insert_us_per / 1000, 2)} ms/op, #{Float.round(insert_qps, 1)} QPS
- Search: #{Float.round(search_us_per / 1000, 2)} ms/op, #{Float.round(search_qps, 1)} QPS
"""

IO.puts(report)
