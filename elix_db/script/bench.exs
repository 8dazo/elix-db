# Run: mix run script/bench.exs [--json]
# Measures insert and search latency; reports mean, p50, p99 (ms), QPS.
# Optional: --json outputs JSON instead of Markdown.
Application.ensure_all_started(:elix_db)

registry = ElixDb.CollectionRegistry
store = ElixDb.Store

json_out = "--json" in System.argv()

# Create collection
ElixDb.CollectionRegistry.create_collection(registry, "bench", 64, :cosine)

defmodule BenchStats do
  def percentile(sorted_list, p) when is_list(sorted_list) and length(sorted_list) > 0 do
    n = length(sorted_list)
    idx = min(div(n * p, 100), n - 1)
    Enum.at(sorted_list, idx)
  end

  def stats(us_list) do
    sorted = Enum.sort(us_list)
    n = length(sorted)
    mean = if n == 0, do: 0, else: Enum.sum(sorted) / n
    p50 = percentile(sorted, 50)
    p99 = percentile(sorted, 99)
    qps = if mean == 0, do: 0, else: 1_000_000 / mean
    %{count: n, mean_us: mean, p50_us: p50, p99_us: p99, mean_ms: mean / 1000, p50_ms: p50 / 1000, p99_ms: p99 / 1000, qps: qps}
  end
end

# Per-operation latencies (single-op timing)
n_inserts = 1000
insert_us_list = for i <- 1..n_inserts do
  vec = for _ <- 1..64, do: :rand.uniform()
  {t_us, _} = :timer.tc(fn -> ElixDb.Store.upsert(store, "bench", "p#{i}", vec, %{}) end)
  t_us
end

n_searches = 100
search_us_list = for _ <- 1..n_searches do
  q = for _ <- 1..64, do: :rand.uniform()
  {t_us, _} = :timer.tc(fn -> ElixDb.Store.search(store, "bench", q, 10) end)
  t_us
end

insert_stats = BenchStats.stats(insert_us_list)
search_stats = BenchStats.stats(search_us_list)

if json_out do
  report = %{
    n_vectors: n_inserts,
    dimension: 64,
    k: 10,
    insert: insert_stats,
    search: search_stats
  }
  IO.puts(Jason.encode!(report))
else
  report = """
  # elix-db benchmark (n=#{n_inserts} vectors, dim=64, k=10)

  ## Insert
  - count: #{insert_stats.count}
  - mean: #{Float.round(insert_stats.mean_ms, 3)} ms
  - p50: #{Float.round(insert_stats.p50_ms, 3)} ms
  - p99: #{Float.round(insert_stats.p99_ms, 3)} ms
  - QPS: #{Float.round(insert_stats.qps, 1)}

  ## Search
  - count: #{search_stats.count}
  - mean: #{Float.round(search_stats.mean_ms, 3)} ms
  - p50: #{Float.round(search_stats.p50_ms, 3)} ms
  - p99: #{Float.round(search_stats.p99_ms, 3)} ms
  - QPS: #{Float.round(search_stats.qps, 1)}
  """
  IO.puts(report)
end
