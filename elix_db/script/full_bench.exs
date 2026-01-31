# Run: mix run script/full_bench.exs [--json] [--dazo] [--n 1000]
#
# 1. Tests all functionality (collections, upsert, get, get_many, search, delete, delete_many, delete_by_filter).
# 2. Benchmarks each operation: latency mean/p50/p99 (ms), QPS.
# 3. Writes results to benchmarks/<timestamp>_results.json and benchmarks/<timestamp>_report.md.
# 4. Report includes actual elix-db numbers and a comparison table vs Qdrant/Milvus/pgvector (reference numbers).
#
# Options:
#   --json     Only write JSON (no markdown report).
#   --dazo     Build DAZO index after inserts and benchmark DAZO search (uses smaller n for build time).
#   --n N      Number of vectors for insert/search bench (default 1000; with --dazo default 300).
Application.ensure_all_started(:elix_db)

registry = ElixDb.CollectionRegistry
store = ElixDb.Store
dazo_index = ElixDb.DazoIndex

argv = System.argv()
json_only = "--json" in argv
dazo_mode = "--dazo" in argv
# Accept --n=N or --n N (argv splits on space so "--n" and "100" are separate)
n_vectors = cond do
  n_arg = Enum.find(argv, fn a -> String.starts_with?(a, "--n=") end) ->
    [_, num] = String.split(n_arg, "=", parts: 2)
    String.to_integer(num)
  idx = Enum.find_index(argv, fn a -> a == "--n" end) ->
    next = Enum.at(argv, idx + 1)
    if next && next =~ ~r/^\d+$/, do: String.to_integer(next), else: if(dazo_mode, do: 300, else: 1000)
  true ->
    if dazo_mode, do: 300, else: 1000
end

dim = 64
k = 10
batch_size = min(200, max(50, div(n_vectors, 5)))
coll_name = "full_bench"

defmodule FullBench do
  def percentile(sorted_list, p) when is_list(sorted_list) and length(sorted_list) > 0 do
    n = length(sorted_list)
    idx = min(div(n * p, 100), n - 1)
    Enum.at(sorted_list, idx)
  end

  def stats(us_list) do
    sorted = Enum.sort(us_list)
    n = length(sorted)
    mean = if n == 0, do: 0.0, else: Enum.sum(sorted) / n
    p50 = if n == 0, do: 0.0, else: percentile(sorted, 50)
    p99 = if n == 0, do: 0.0, else: percentile(sorted, 99)
    qps = if mean == 0, do: 0.0, else: 1_000_000 / mean
    %{count: n, mean_us: mean, p50_us: p50, p99_us: p99, mean_ms: mean / 1000, p50_ms: p50 / 1000, p99_ms: p99 / 1000, qps: qps}
  end

  def time_us(fun) do
    {t_us, _} = :timer.tc(fun)
    t_us
  end
end

# ----- Functionality tests -----
functionality = %{}

functionality =
  try do
    # Clean slate
    ElixDb.CollectionRegistry.delete_collection(registry, coll_name)

    # Create collection
    {:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)
    list = ElixDb.CollectionRegistry.list_collections(registry)
    names = Enum.map(list, & &1.name)
    functionality = Map.put(functionality, :collection_create_list, "full_bench" in names)

    coll = ElixDb.CollectionRegistry.get_collection(registry, coll_name)
    functionality = Map.put(functionality, :collection_get, coll != nil and coll.dimension == dim)

    # Upsert single + get
    vec1 = for _ <- 1..dim, do: :rand.uniform()
    :ok = ElixDb.Store.upsert(store, coll_name, "p1", vec1, %{tag: "a"})
    got = ElixDb.Store.get(store, coll_name, "p1", with_vector: true)
    functionality = Map.put(functionality, :upsert_get, got != nil and got.id == "p1" and length(got.vector) == dim)

    # Upsert batch
    points = for i <- 2..(batch_size + 1) do
      vec = for _ <- 1..dim, do: :rand.uniform()
      {"p#{i}", vec, %{idx: i, tag: if(rem(i, 2) == 0, do: "even", else: "odd")}}
    end
    :ok = ElixDb.Store.upsert_batch(store, coll_name, points)
    functionality = Map.put(functionality, :upsert_batch, true)

    # Get many
    ids = Enum.map(2..11, fn i -> "p#{i}" end)
    many = ElixDb.Store.get_many(store, coll_name, ids)
    functionality = Map.put(functionality, :get_many, length(many) == 10)

    # Search (no filter)
    {:ok, results} = ElixDb.Store.search(store, coll_name, vec1, k)
    functionality = Map.put(functionality, :search, length(results) >= 1 and hd(results).id == "p1")

    # Search with filter
    {:ok, filtered} = ElixDb.Store.search(store, coll_name, vec1, k, filter: %{"tag" => "even"})
    functionality = Map.put(functionality, :search_filter, is_list(filtered))

    # Delete single
    ElixDb.Store.delete(store, coll_name, "p1")
    functionality = Map.put(functionality, :delete, ElixDb.Store.get(store, coll_name, "p1") == nil)

    # Delete many
    del_ids = Enum.map(2..6, fn i -> "p#{i}" end)
    ElixDb.Store.delete_many(store, coll_name, del_ids)
    remaining = ElixDb.Store.get_many(store, coll_name, Enum.map(7..11, fn i -> "p#{i}" end))
    functionality = Map.put(functionality, :delete_many, length(remaining) == 5)

    # Delete by filter
    ElixDb.Store.delete_by_filter(store, coll_name, %{"tag" => "odd"})
    odd_left = ElixDb.Store.search(store, coll_name, vec1, 100, filter: %{"tag" => "odd"})
    functionality = Map.put(functionality, :delete_by_filter, elem(odd_left, 1) == [])

    functionality
  rescue
    e -> Map.put(functionality, :error, inspect(e))
  end

functionality_ok = not Map.has_key?(functionality, :error) and Enum.all?(Map.drop(functionality, [:error]), & &1)

# Recreate collection for benchmark phase (clean state)
ElixDb.CollectionRegistry.delete_collection(registry, coll_name)
{:ok, _} = ElixDb.CollectionRegistry.create_collection(registry, coll_name, dim, :cosine)

# ----- Benchmark: upsert single -----
n_insert = min(n_vectors, 2000)
insert_us = for i <- 1..n_insert do
  vec = for _ <- 1..dim, do: :rand.uniform()
  FullBench.time_us(fn -> ElixDb.Store.upsert(store, coll_name, "b#{i}", vec, %{i: i}) end)
end
insert_stats = FullBench.stats(insert_us)

# ----- Benchmark: upsert batch -----
# In DAZO mode with small n, skip extra batch points so DAZO build runs on ~n_vectors points
n_batches = if dazo_mode and n_vectors < 200, do: 0, else: max(1, div(n_vectors, batch_size))
batch_us = for _ <- Enum.take(1..20, n_batches) do
  pts = for _ <- 1..batch_size do
    id = "batch_#{:rand.uniform(1_000_000)}"
    vec = for _ <- 1..dim, do: :rand.uniform()
    {id, vec, %{}}
  end
  FullBench.time_us(fn -> ElixDb.Store.upsert_batch(store, coll_name, pts) end)
end
batch_stats = FullBench.stats(batch_us)
batch_per_point_us = if batch_stats.count > 0, do: batch_stats.mean_us / batch_size, else: 0

# ----- Benchmark: get -----
get_ids = Enum.map(1..min(100, n_insert), fn i -> "b#{i}" end)
get_us = for id <- get_ids do
  FullBench.time_us(fn -> ElixDb.Store.get(store, coll_name, id) end)
end
get_stats = FullBench.stats(get_us)

# ----- Benchmark: get_many -----
chunk = Enum.take(get_ids, 20)
get_many_us = for _ <- 1..50 do
  FullBench.time_us(fn -> ElixDb.Store.get_many(store, coll_name, chunk) end)
end
get_many_stats = FullBench.stats(get_many_us)

# ----- Benchmark: search (brute-force) -----
n_search = 100
search_us = for _ <- 1..n_search do
  q = for _ <- 1..dim, do: :rand.uniform()
  FullBench.time_us(fn -> ElixDb.Store.search(store, coll_name, q, k) end)
end
search_brute_stats = FullBench.stats(search_us)

# ----- DAZO (optional) -----
{dazo_build_ms, search_dazo_stats} =
  if dazo_mode do
    build_start = System.monotonic_time(:millisecond)
    :ok = ElixDb.DazoIndex.build(dazo_index, store, coll_name, registry: registry, timeout: 120_000, full_scan_threshold: 0)
    build_ms = System.monotonic_time(:millisecond) - build_start
    dazo_us = for _ <- 1..n_search do
      q = for _ <- 1..dim, do: :rand.uniform()
      FullBench.time_us(fn -> ElixDb.Store.search(store, coll_name, q, k) end)
    end
    {build_ms, FullBench.stats(dazo_us)}
  else
    {nil, nil}
  end

# ----- Benchmark: delete single -----
delete_us = for i <- (n_insert + 1)..(n_insert + 100) do
  vec = for _ <- 1..dim, do: :rand.uniform()
  ElixDb.Store.upsert(store, coll_name, "del#{i}", vec, %{})
  FullBench.time_us(fn -> ElixDb.Store.delete(store, coll_name, "del#{i}") end)
end
delete_stats = FullBench.stats(delete_us)

# ----- Benchmark: delete_many -----
dm_ids = for i <- 1..20, do: "dm#{i}"
for {id, _} <- Enum.with_index(dm_ids) do
  vec = for _ <- 1..dim, do: :rand.uniform()
  ElixDb.Store.upsert(store, coll_name, id, vec, %{})
end
delete_many_us = FullBench.time_us(fn -> ElixDb.Store.delete_many(store, coll_name, dm_ids) end)
delete_many_stats = %{count: 1, mean_us: delete_many_us, p50_us: delete_many_us, p99_us: delete_many_us, mean_ms: delete_many_us / 1000, p50_ms: delete_many_us / 1000, p99_ms: delete_many_us / 1000, qps: 1_000_000 / delete_many_us}

# ----- Memory -----
memory_mb = try do
  pid = Process.whereis(store)
  if pid && Process.alive?(pid), do: Process.info(pid, :memory) |> elem(1) |> Kernel./(1_048_576) |> Float.round(3), else: nil
rescue
  _ -> nil
end

# ----- Recall check (self-query) -----
recall_ok = try do
  p = ElixDb.Store.get(store, coll_name, "b1", with_vector: true)
  if p && p.vector do
    {:ok, res} = ElixDb.Store.search(store, coll_name, p.vector, 1)
    length(res) >= 1 and hd(res).id == "b1"
  else
    false
  end
rescue
  _ -> false
end

# ----- Build report -----
ts = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[-:.]/, "") |> String.slice(0..13)
out_dir = Path.join(File.cwd!(), "benchmarks")
File.mkdir_p!(out_dir)
json_path = Path.join(out_dir, "#{ts}_results.json")
md_path = Path.join(out_dir, "#{ts}_report.md")

report_json = %{
  timestamp: ts,
  options: %{n_vectors: n_vectors, dim: dim, k: k, dazo: dazo_mode, batch_size: batch_size},
  functionality_ok: functionality_ok,
  functionality: functionality,
  recall_self_ok: recall_ok,
  memory_mb: memory_mb,
  benchmarks: %{
    upsert_single: insert_stats,
    upsert_batch: Map.put(batch_stats, :per_point_us, batch_per_point_us),
    get: get_stats,
    get_many: get_many_stats,
    search_brute: search_brute_stats,
    search_dazo: search_dazo_stats,
    delete: delete_stats,
    delete_many: delete_many_stats
  },
  dazo_build_ms: dazo_build_ms
}

File.write!(json_path, Jason.encode!(report_json, pretty: true))
IO.puts("Wrote #{json_path}")

unless json_only do
  # Reference numbers (typical single-node; not from this run). Source: docs/benchmarks.md + common benchmarks.
  ref_qdrant = "Qdrant (1M vec, dim 1536, HNSW)"
  ref_milvus = "Milvus (1M vec, dim 1536, HNSW)"
  ref_pgvector = "pgvector (1M vec, dim 1536, HNSW)"

  md = """
  # elix-db Full Benchmark Report — #{ts}

  ## Functionality

  All core operations exercised: **#{if functionality_ok, do: "PASS", else: "FAIL"}**

  | Test | Result |
  |------|--------|
  | collection create / list / get | #{Map.get(functionality, :collection_create_list, false) && Map.get(functionality, :collection_get, false)} |
  | upsert single + get | #{Map.get(functionality, :upsert_get, false)} |
  | upsert batch | #{Map.get(functionality, :upsert_batch, false)} |
  | get_many | #{Map.get(functionality, :get_many, false)} |
  | search | #{Map.get(functionality, :search, false)} |
  | search with filter | #{Map.get(functionality, :search_filter, false)} |
  | delete | #{Map.get(functionality, :delete, false)} |
  | delete_many | #{Map.get(functionality, :delete_many, false)} |
  | delete_by_filter | #{Map.get(functionality, :delete_by_filter, false)} |

  ## Actual Performance (this run)

  **Config:** n=#{n_vectors}, dim=#{dim}, k=#{k}, batch_size=#{batch_size}#{if dazo_mode, do: ", DAZO index built", else: ""}

  | Operation | Count | Mean (ms) | p50 (ms) | p99 (ms) | QPS |
  |-----------|-------|-----------|----------|----------|-----|
  | upsert_single | #{insert_stats.count} | #{Float.round(insert_stats.mean_ms, 4)} | #{Float.round(insert_stats.p50_ms, 4)} | #{Float.round(insert_stats.p99_ms, 4)} | #{Float.round(insert_stats.qps, 1)} |
  | upsert_batch (#{batch_size}/batch) | #{batch_stats.count} | #{Float.round(batch_stats.mean_ms, 2)} | #{Float.round(batch_stats.p50_ms, 2)} | #{Float.round(batch_stats.p99_ms, 2)} | #{Float.round(batch_stats.qps, 1)} |
  | get | #{get_stats.count} | #{Float.round(get_stats.mean_ms, 4)} | #{Float.round(get_stats.p50_ms, 4)} | #{Float.round(get_stats.p99_ms, 4)} | #{Float.round(get_stats.qps, 1)} |
  | get_many (20 ids) | #{get_many_stats.count} | #{Float.round(get_many_stats.mean_ms, 4)} | #{Float.round(get_many_stats.p50_ms, 4)} | #{Float.round(get_many_stats.p99_ms, 4)} | #{Float.round(get_many_stats.qps, 1)} |
  | search (brute-force) | #{search_brute_stats.count} | #{Float.round(search_brute_stats.mean_ms, 2)} | #{Float.round(search_brute_stats.p50_ms, 2)} | #{Float.round(search_brute_stats.p99_ms, 2)} | #{Float.round(search_brute_stats.qps, 1)} |
  """ |> String.trim()

  md = if dazo_mode and search_dazo_stats do
    md <> """
  | search (DAZO) | #{search_dazo_stats.count} | #{Float.round(search_dazo_stats.mean_ms, 2)} | #{Float.round(search_dazo_stats.p50_ms, 2)} | #{Float.round(search_dazo_stats.p99_ms, 2)} | #{Float.round(search_dazo_stats.qps, 1)} |
  | DAZO build | — | #{dazo_build_ms} ms total | — | — | — |
  """
  else
    md <> "\n"
  end

  md = md <> """
  | delete | #{delete_stats.count} | #{Float.round(delete_stats.mean_ms, 4)} | #{Float.round(delete_stats.p50_ms, 4)} | #{Float.round(delete_stats.p99_ms, 4)} | #{Float.round(delete_stats.qps, 1)} |
  | delete_many (20 ids) | 1 | #{Float.round(delete_many_stats.mean_ms, 2)} | — | — | #{Float.round(delete_many_stats.qps, 1)} |

  **Memory (Store process):** #{memory_mb || "N/A"} MB  
  **Recall (self-query b1):** #{recall_ok}

  ## Comparison vs other vector DBs (actual vs reference)

  *elix-db numbers are from this run. Qdrant/Milvus/pgvector numbers are typical single-node reference values (different scale/hardware); run your own for direct comparison.*

  | System | n | dim | Insert p99 (ms) | Insert QPS | Search p99 (ms) | Search QPS | Index |
  |--------|---|-----|-----------------|------------|-----------------|------------|-------|
  | **elix-db (this run)** | #{n_vectors} | #{dim} | #{Float.round(insert_stats.p99_ms, 4)} | #{Float.round(insert_stats.qps, 0)} | #{Float.round(search_brute_stats.p99_ms, 2)} | #{Float.round(search_brute_stats.qps, 1)} | brute |
  """

  md = if dazo_mode and search_dazo_stats do
    md <> "| **elix-db DAZO (this run)** | #{n_vectors} | #{dim} | — | — | #{Float.round(search_dazo_stats.p99_ms, 2)} | #{Float.round(search_dazo_stats.qps, 1)} | DAZO |\n"
  else
    md
  end

  md = md <> """
  | #{ref_qdrant} | 1M | 1536 | &lt;1 | 10k+ | &lt;1–few | 1k+ | HNSW |
  | #{ref_milvus} | 1M | 1536 | &lt;1 | 10k+ | &lt;1–few | 1k+ | HNSW |
  | #{ref_pgvector} | 1M | 1536 | ms | hundreds | ms | hundreds | HNSW |

  **Takeaway:** elix-db gives you **actual numbers on your hardware** in this report. For similar n/dim, compare your search QPS and p99 to the table above. At small n (e.g. #{n_vectors}) brute-force is exact but O(n); DAZO reduces search latency when built. For million-scale or sub-ms SLA, use Qdrant/Milvus/pgvector.
  """

  File.write!(md_path, md)
  IO.puts("Wrote #{md_path}")
end

IO.puts("Functionality: #{if functionality_ok, do: "PASS", else: "FAIL"}")
IO.puts("Results: #{json_path}" <> (if json_only, do: "", else: " + #{md_path}"))
