# Performance and scaling: why elix-db is slower than industry and how to improve

## Why industry vector DBs do “millions in ms”

Systems like **Qdrant**, **Milvus**, and **pgvector** achieve sub‑ms or low‑ms search at millions of vectors because they:

1. **Don’t scan all vectors**  
   They use **approximate indexes** (HNSW, IVF, etc.) so each query does only a small, bounded number of distance computations (e.g. hundreds), not O(n).

2. **Use native code**  
   Hot paths (distance, graph traversal) are in Rust/C++ with SIMD; elix-db uses Nx/Elixir.

3. **Optimize memory and I/O**  
   Vectors are stored in contiguous or memory‑mapped layouts; elix-db uses ETS + list-of-lists and builds Nx tensors per query.

4. **Scale out**  
   They support sharding and distributed search; elix-db is single-node and in-memory.

So “millions in ms” comes from **approximate search + native code + scale**, not from brute-force.

---

## Why elix-db is slower

- **Brute-force search is O(n)**  
  Every query scans all points and does Nx batch similarity. At 10k vectors that’s 10k distances per query; at 1M it’s 1M. Latency grows with n.

- **No incremental index**  
  DAZO is built once over the full set; there’s no HNSW-style incremental update. Build time grows with n.

- **Elixir/Nx, not native**  
  Nx is fast but not at the level of hand-tuned SIMD in Rust/C++; ETS + list handling add overhead.

---

## How to improve performance

### 1. Use DAZO for search when n is large

- **n ≤ full_scan_threshold** (default 500): no index is built; search is brute-force. Keep small collections fast without index overhead.
- **full_scan_threshold < n < coarse_threshold** (500–5k): DAZO builds an **HNSW-style multi-layer graph** (Qdrant/Milvus-like). Search: entry → descend → search_on_level(ef) → **Nx batch re-rank**. Tune **M** (max edges, default 16), **ef_construct** (build, default 100), **ef** (search).
- **n ≥ coarse_threshold** (default 5k): DAZO builds **IVF-style coarse quantizer** (k-means on sketches → buckets). Search: probe **nprobe** buckets → collect ids → **Nx batch re-rank**. Tune **nlist**, **nprobe**.

See [DAZO.md](../../DAZO.md) for architecture and [benchmarks.md](benchmarks.md) for comparison vs Qdrant/Milvus.

```elixir
# After bulk load
:ok = ElixDb.DazoIndex.build(ElixDb.DazoIndex, ElixDb.Store, collection_name, registry: ElixDb.CollectionRegistry, timeout: 120_000)
# All subsequent searches use DAZO until you change the store and rebuild
{:ok, results} = ElixDb.Store.search(ElixDb.Store, collection_name, query_vec, k)
```

Trade-off: build is one-time and can be slow (tens of seconds for hundreds of points); rebuild when you do large updates.

### 2. Prefer batch upserts

Use `Store.upsert_batch/3` instead of many single `upsert/5` calls to reduce round-trips and batching overhead.

### 3. Keep n small if you need brute-force

If you must use brute-force (exact k-NN, no index), keep collections under roughly 10k–50k vectors so latency stays acceptable. Above that, use DAZO or an external system.

### 4. When you really need “millions in ms”

Use an external vector DB:

- **pgvector** – good if you’re already on Postgres; HNSW/IVFFlat; scales to millions.
- **Qdrant / Milvus** – dedicated vector DBs; HNSW; sub-ms at large scale.

elix-db is aimed at small/medium in-process workloads, prototypes, and exact or DAZO-accelerated search, not at replacing those for very large scale.

---

## What we optimized in elix-db

- **Similarity batch APIs** accept an Nx tensor of shape `{n, dim}` as well as a list of vectors, so the Store builds the tensor once and passes it, avoiding a second conversion inside Similarity.
- **Nx batch re-rank:** When using DAZO (HNSW, IVF, or graph), the Store re-ranks candidates with a single **cosine_batch/l2_batch/dot_product_batch** call instead of per-point similarity, reducing re-rank cost.
- **HNSW-style index:** For medium n (500–5k), multi-layer graph with M/ef_construct/ef aligns with Qdrant/Milvus; search does log-like hops then re-rank.
- **Brute-force path** still does one full scan and one Nx batch similarity per query; the main lever for large n is using DAZO.

---

## Summary

| Goal                         | Use in elix-db                          |
|-----------------------------|-----------------------------------------|
| Lower search latency, n > full_scan_threshold | Build **DAZO** (HNSW or IVF); use **ef**, **nprobe**; re-rank is Nx batch. |
| Exact k-NN, small n (≤500)  | Brute-force (no index build).           |
| Tuning HNSW                 | **M** (16–32), **ef_construct** (100–200), **ef** (50–200). |
| Tuning IVF                  | **nlist**, **nprobe** (e.g. 8).          |
| Millions of vectors, ms latency | Use **pgvector**, **Qdrant**, or **Milvus**. |

So: **use DAZO for larger n**, and treat “millions in ms” as the domain of dedicated, approximate-index systems rather than in-process brute-force.
