---
name: debug-verify-benchmark
description: Debug, verify, and compare elix-db to industry after each plan step. Use after implementing any plan step or changing vector/store/API logic; run tests, IEx checks, and document efficiency vs Qdrant/Milvus/pgvector.
---

# Debug, Verify, and Benchmark

Apply after every plan step or change to vector store, search, or API.

## When to Use

- After implementing a step in plan/README.md
- After changing `ElixDb` vector/store/API logic
- Before marking a step "Done" in the plan

## Debug

1. **Run tests:** `mix test`
2. **Start IEx:** `iex -S mix` and exercise the new APIs (create collection, upsert, search, get, delete as applicable).
3. **Add traces if needed:** `Logger.debug/2` or `:sys.trace` for GenServer; fix failures before proceeding.

## Verify

1. All tests pass; no new compiler warnings.
2. For search: add or run tests that check known vectors produce known ordering (e.g. cosine similarity order).
3. Acceptance criteria in the step file are checked off.

## Industry Comparison

For each step, fill in the **Industry comparison** table in the step file:

- **Correctness:** Behavior matches Qdrant/Milvus (collections, points, upsert, search, get, delete).
- **Latency:** Note expected vs actual; compare to typical Qdrant/Milvus/pgvector numbers (e.g. p99 ms) when metrics exist.
- **Throughput:** QPS if measured; document concurrency level.
- **Recall:** For search, recall@k = 1.0 for exact k-NN; document when approximate index is added later.

Document **efficiency notes** at the bottom of the step: gaps, improvement ideas, and follow-up tasks.

## Metrics to Capture

When implementing step 8 or ad-hoc benchmarking:

| Metric | How | Use |
|--------|-----|-----|
| Latency | Per-operation timing; compute mean, p50, p99 | Compare to industry; track over time |
| QPS | Queries per second under fixed concurrency | Throughput vs Qdrant/Milvus |
| Recall@k | True k-NN vs returned k; fraction overlap | Search quality when ground truth exists |
| Memory/CPU | BEAM process stats | Resource efficiency |

Store results in a simple format (e.g. JSON struct or Markdown table) under `docs/benchmarks.md` or script output for future comparison.
