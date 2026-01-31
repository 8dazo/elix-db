# elix_db v2 Report

## Stress test (10k vectors)

- **Run:** `mix test test/stress_test.exs`
- **Results:** 2 tests, 0 failures
  - 10k vectors: upsert, search correctness, and latency — ~946 ms
  - 10k vectors: batch upsert and search — ~888 ms
- **Correctness:** Query with stored vector returns self first; score ≥ 0.999. Search latency &lt; 10s.

## Sample use cases: v0.2.0 vs v0.1.0

Benchmark runner: `cd sample_uses && elixir script/run_bench.exs v0.2.0 v0.1.0`

| Use case | Metric | v0.1.0 | v0.2.0 | Delta |
|----------|--------|--------|--------|-------|
| 01_simple_search | wall_us | 29186 | 9824 | -66.3% |
| 01_simple_search | memory_bytes | 2492073 | 472582 | -81.0% |
| 02_semantic_faq | wall_us | 28742 | 8552 | -70.2% |
| 02_semantic_faq | memory_bytes | 2495199 | 435651 | -82.5% |
| 03_similar_items | wall_us | 87992 | 7107 | -91.9% |
| 03_similar_items | memory_bytes | 2514361 | 469414 | -81.3% |
| 04_persistence | wall_us | 26124 | 7497 | -71.3% |
| 04_persistence | memory_bytes | 2526341 | 452296 | -82.1% |

**Summary:** v0.2.0 sample use cases show large improvements in wall time (66–92% lower) and memory (81–82% lower) vs v0.1.0.

Full comparison: [sample_uses/reports/v0.2.0_vs_v0.1.0.md](../../sample_uses/reports/v0.2.0_vs_v0.1.0.md)
