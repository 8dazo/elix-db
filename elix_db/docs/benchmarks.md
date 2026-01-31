# elix-db Benchmarks vs Industry

## How to run

**Full functionality + benchmarks (recommended):**

```bash
cd elix_db
mix run script/full_bench.exs          # all ops + latency + comparison table
mix run script/full_bench.exs --dazo  # same + DAZO index and DAZO search
mix run script/full_bench.exs --n 500 --json  # fewer vectors, JSON only
```

Writes **actual numbers** to `benchmarks/<timestamp>_results.json` and `benchmarks/<timestamp>_report.md`. The report includes a comparison table vs Qdrant/Milvus/pgvector (reference numbers). Tests all functionality: collections, upsert single/batch, get, get_many, search (with filter), delete, delete_many, delete_by_filter.

**Quick insert + search only:**

```bash
mix run script/bench.exs
```

Default: 1000 vectors, dimension 64, k=10. Reports mean, p50, p99 (ms) and QPS for insert and search.

- **`--dazo`** – Build a DAZO index after inserts, then run search again; report both brute-force and DAZO search latency/QPS. Uses n=300 so index build finishes in ~20–30 s.
- **`--json`** – Output JSON instead of Markdown.

## Metrics to capture

| Metric | Description |
|--------|-------------|
| Latency | Mean, p50, p99 per operation (insert, search, get, delete) |
| QPS | Queries per second under fixed concurrency |
| Recall@k | For search: fraction of true k-NN in returned k (when ground truth available) |

## Measured baseline (elix-db)

| n | dim | k | Mode | Insert ms/op | Insert QPS | Search ms/op | Search QPS |
|---|-----|---|------|-------------|------------|--------------|------------|
| 1k | 64 | 10 | brute-force | ~0.01 | ~162k | ~90 | ~11 |
| 300 | 64 | 10 | DAZO (--dazo) | — | — | ~5 ms | ~206 |
| 2k | 32 | 10 | (verification test) | — | — | — | — |

- **Insert:** O(1) per point; very high QPS. Batch upsert available.
- **Search (default):** When a DAZO index exists, search uses it (graph + Hamming + predicate pruning, then re-rank). Pass `brute_force: true` to force exact brute-force.
- **Search (brute-force):** Exact k-NN is O(n) per query; batch Nx similarity. Used when no index exists or when `brute_force: true` is passed.
- **Search (DAZO):** With `--dazo`, benchmark uses n=300 (so build finishes in ~20–30 s); DAZO search is typically 3–4× faster than brute-force (e.g. ~5 ms vs ~14 ms at n=300). For n between `full_scan_threshold` (500) and `coarse_threshold` (5k), DAZO builds an **HNSW-style multi-layer graph** (Qdrant/Milvus-like); re-rank uses **Nx batch** distance.

## Comparison vs industry

| System | n | dim | Insert p99 | Search p99 | Search QPS | Index |
|--------|---|-----|------------|------------|------------|-------|
| elix-db (brute-force) | 1k | 64 | ~0.01 ms | ~90 ms | ~11 | none |
| elix-db (DAZO graph) | 300 | 64 | — | ~5 ms | ~206 | graph + sketches |
| elix-db (HNSW) | 500–5k | 64 | — | low ms | higher | multi-layer HNSW |
| elix-db (IVF) | 10k | 32 | — | low ms | — | coarse quantizer |
| Qdrant (single-node) | 1M | 1536 | sub-ms | sub-ms to ms | 1k+ | HNSW |
| Milvus | 1M | 1536 | sub-ms | sub-ms to ms | 1k+ | IVF_FLAT / HNSW |
| pgvector | 1M | 1536 | ms | ms | hundreds | IVFFlat / HNSW |

Use same or similar workload for fair comparison. elix-db HNSW mode aligns with Qdrant/Milvus algorithm (multi-layer, M/ef_construct/ef, full_scan_threshold). DAZO is in-memory and requires rebuild after bulk changes; for billion-scale or disk-backed indexes see DAZO.md and industry systems.

---

## Production readiness assessment

**Good for:** Small to medium workloads (e.g. &lt; 50k–100k vectors per collection), prototypes, internal tools, exact k-NN or DAZO-accelerated filtered search.

**Strengths:**
- **Correctness:** API aligns with Qdrant/Milvus subset (collections, points, upsert, k-NN search, get, delete, payload filter). Cosine, L2, dot product. Recall@k = 1.0 for exact k-NN; DAZO re-ranks with full vectors.
- **DAZO:** Optional index: **HNSW-style** (n between full_scan_threshold and coarse_threshold), **IVF** (n ≥ coarse_threshold), or legacy Vamana graph. Build via `DazoIndex.build/4`; search uses HNSW/IVF/graph then **Nx batch re-rank**. Options: `full_scan_threshold`, `m`, `ef_construct`, `ef`, `nprobe`.
- **Tests:** Unit tests, property-based tests (StreamData), DAZO tests (EAB, Graph, PredicateMask, DazoIndex), verification and stress tests; persistence and load-from-disk covered.
- **Features:** Collections, batch upsert, get_many, delete_by_filter, file persistence (Store + DAZO index), HTTP API, metrics, benchmark script (`--dazo` for index mode).

**Current limitations:**
- **Scale:** Brute-force search is O(n). DAZO index is in-memory; must be **rebuilt** after bulk Store changes (no incremental update). Not aimed at billion-scale or sub-ms SLA at huge n.
- **DAZO scope:** EAB uses per-dimension median (not full entropy-adaptive); graph is in-memory (no disk/io_uring); 8-bit predicate masks (up to 8 filter categories).
- **Persistence:** Single-file binary term; no WAL, no point-in-time recovery. Optional `persist_interval_sec` and `persist_after_batch` reduce data-loss window.
- **Operational:** Single-node; HTTP has no auth/rate limiting; Telemetry `[:elix_db, :store, operation]` and metrics exist but no built-in dashboards.

**Verdict:** elix-db is a **solid small-scale vector DB** with exact and optional DAZO-accelerated search, correct semantics, and good test coverage. For very large scale or incremental indexes, consider pgvector, Qdrant, or Milvus.

See **[performance.md](performance.md)** for why elix-db is slower than industry at large scale and how to improve (use DAZO, batch upserts, when to use external DBs).
