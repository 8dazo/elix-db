# elix-db Build Plan

This folder contains the step-by-step plan to build elix-db from scratch, replicating Qdrant/Milvus-style behavior.

## Order of Steps

| Step | File | Summary |
|------|------|---------|
| 1 | [step-01-scaffold.md](step-01-scaffold.md) | Mix project, ElixDb.Application, supervision |
| 2 | [step-02-collections.md](step-02-collections.md) | Collection creation (name, dimension, distance metric) |
| 3 | [step-03-points-storage.md](step-03-points-storage.md) | Points: insert/upsert, ETS-backed per collection |
| 4 | [step-04-search.md](step-04-search.md) | Exact k-NN search (cosine or L2) |
| 5 | [step-05-get-and-delete.md](step-05-get-and-delete.md) | Get by id(s), delete by id or filter |
| 6 | [step-06-persistence.md](step-06-persistence.md) | File-based save/load |
| 7 | [step-07-http-api.md](step-07-http-api.md) | Optional HTTP API (Plug) |
| 8 | [step-08-metrics-and-benchmark.md](step-08-metrics-and-benchmark.md) | Latency, QPS, recall@k; run and compare |

Execute steps in order. Do not skip steps.

## Per-Step Workflow

For each step:

1. **Goal** – Read what is being implemented.
2. **Tasks** – Implement the listed tasks (files/modules).
3. **Debug** – Run tests, IEx, and manual checks as described.
4. **Verify** – Confirm acceptance criteria and tests pass.
5. **Industry comparison** – Fill in the checklist vs Qdrant/Milvus/pgvector; note efficiency gaps and improvement ideas.

When a step is done, mark it **Done** in the step file and add any efficiency notes.

## Debug, Verify, and Benchmark

Apply the project skill **debug-verify-benchmark** after each step:

- Run `mix test`.
- Use IEx to exercise the new APIs.
- Compare behavior and efficiency to industry (Qdrant, Milvus, pgvector).
- Capture metrics (latency, QPS, recall@k) where applicable.

## Benchmarks vs Industry

After all steps, capture baseline metrics and document "elix-db vs industry" in this README or in `docs/benchmarks.md`.

### elix-db vs industry (summary)

- **Implementation:** All 8 steps done. Collections, points (upsert/get/delete/search), file persistence, HTTP API, and metrics/bench script are in place.
- **Correctness:** API aligns with Qdrant/Milvus subset (collections, points, upsert, k-NN search, get, delete, payload filter).
- **Efficiency:** Exact k-NN is O(n) per query; insert is O(1) per point. For small/medium n (e.g. &lt; 100k) this is acceptable. For scale, consider pgvector (HNSW/IVFFlat) or external engine.
- **Baseline:** Run `mix run script/bench.exs` from `elix_db/`; see `elix_db/docs/benchmarks.md` for comparison table and improvement notes.
