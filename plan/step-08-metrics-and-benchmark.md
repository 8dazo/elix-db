# Step 8: Metrics and Benchmark

**Status:** Done

## Goal

Add **instrumentation and benchmarking**: measure latency (e.g. mean, p50, p99) per operation (insert, search, get, delete), throughput (QPS), and recall@k for search when ground truth is available. Output results to logs or a report (e.g. Markdown/JSON) so we can compare runs and track improvements vs industry (Qdrant, Milvus, pgvector).

## Tasks

- [ ] Add a small `ElixDb.Metrics` module (or equivalent): record operation timings (e.g. `:telemetry` or simple aggregate in process). Compute mean, p50, p99 for each operation type.
- [ ] Optional: `ElixDb.Benchmark` or script under `bench/`/`script/`: run N inserts, M searches, etc.; report latency and QPS. Output to stdout or file (JSON/Markdown).
- [ ] For search: if test set with ground truth exists, compute recall@k (fraction of true k-NN found in returned k). Document how to run and interpret.
- [ ] Document in README or `docs/benchmarks.md`: how to run benchmarks; baseline numbers for a chosen dataset/size; comparison table vs industry (e.g. “Qdrant single-node 1M vectors: X ms p99; elix-db same: Y ms”).

## Debug

- Run benchmark script or call Metrics after a workload; inspect reported latencies and QPS. Sanity-check: search latency should scale roughly with collection size for exact k-NN.

## Verify

- [ ] Metrics module does not crash under load; reported percentiles are plausible. Benchmark script runs end-to-end and produces a report.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Latency | Sub-ms to ms, p99 reported | Mean, p50, p99 per op | Aligned. |
| Throughput | QPS under concurrency | QPS measured in benchmark | Document concurrency level. |
| Recall | Recall@k for ANN | Recall@k for exact k-NN (1.0) or future ANN | Set baseline; track if approximate index added. |

**Efficiency notes:** Document dataset size (n, dimension), k, and hardware so comparisons are fair. Use same or similar workload as public Qdrant/Milvus benchmarks where possible. Plan improvements (e.g. approximate index, batching) based on gaps.
