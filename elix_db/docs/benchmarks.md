# elix-db Benchmarks vs Industry

## How to run

```bash
cd elix_db
mix run script/bench.exs
```

Default: 1000 vectors, dimension 64, k=10. Reports mean, p50, p99 (ms) and QPS for insert and search. Use `mix run script/bench.exs --json` for JSON output.

## Metrics to capture

| Metric | Description |
|--------|-------------|
| Latency | Mean, p50, p99 per operation (insert, search, get, delete) |
| QPS | Queries per second under fixed concurrency |
| Recall@k | For search: fraction of true k-NN in returned k (when ground truth available) |

## Measured baseline (elix-db)

| n | dim | k | Insert ms/op | Insert QPS | Search ms/op | Search QPS |
|---|-----|---|-------------|------------|--------------|------------|
| 1k | 64 | 10 | ~0.01 | ~162k | ~90 | ~11 |
| 2k | 32 | 10 | (verification test) | — | — | — |

- **Insert:** O(1) per point; very high QPS. Batch upsert available.
- **Search:** Exact k-NN is O(n) per query; search latency scales linearly with collection size. At 10k vectors expect ~900 ms/query; at 100k, ~9 s/query.

## Comparison vs industry

| System | n | dim | Insert p99 | Search p99 | Search QPS | Index |
|--------|---|-----|------------|------------|------------|-------|
| elix-db (exact k-NN) | 1k | 64 | ~0.01 ms | ~90 ms | ~11 | none (brute force) |
| Qdrant (single-node) | 1M | 1536 | sub-ms | sub-ms to ms | 1k+ | HNSW |
| Milvus | 1M | 1536 | sub-ms | sub-ms to ms | 1k+ | IVF_FLAT / HNSW |
| pgvector | 1M | 1536 | ms | ms | hundreds | IVFFlat / HNSW |

Use same or similar workload for fair comparison. Plan improvements (e.g. approximate index, batching) based on gaps.

---

## Production readiness assessment

**Good for:** Small to medium workloads (e.g. &lt; 50k–100k vectors per collection), prototypes, internal tools, correctness-critical exact k-NN.

**Strengths:**
- **Correctness:** API aligns with Qdrant/Milvus subset (collections, points, upsert, k-NN search, get, delete, payload filter). Cosine and L2 with verified ordering. Recall@k = 1.0 for exact k-NN.
- **Tests:** Unit tests, property-based tests (StreamData: upsert/get, search, delete, get_many, collection creation), and verification tests at 2k vectors and concurrent readers; persistence and load-from-disk covered.
- **Features:** Collections, batch upsert, get_many, delete_by_filter, file persistence, HTTP API, metrics module, benchmark script.

**Gaps vs a “perfect” production DB:**
- **Scale:** No approximate index (HNSW/IVFFlat). Search is O(n); not suitable for millions of vectors without an index.
- **Persistence:** Single file, binary term; no WAL, no point-in-time recovery. Optional `persist_interval_sec` and `persist_after_batch` reduce the window of data loss.
- **Observability:** Metrics are wired into Store; benchmark script reports mean, p50, p99; optional Telemetry events `[:elix_db, :store, operation]`.
- **API:** HTTP has batch upsert (`POST .../points/batch`) and `GET /health`; no auth, no rate limiting, no OpenAPI.
- **Hardening:** No stress tests at 100k+ vectors. Property-based tests (StreamData) cover upsert/get, search, delete, get_many, and collection creation.

**Verdict:** elix-db is a **solid small-scale vector DB** with correct semantics and good test coverage, not just a toy. For production at large scale, add an approximate index and/or use pgvector/Qdrant/Milvus for big collections.
