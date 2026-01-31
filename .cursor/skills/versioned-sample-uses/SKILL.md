---
name: versioned-sample-uses
description: When publishing a new elix-db version or making version changes, run versioned sample use cases, collect memory/time/latency, compare to the previous version report, and update reports. Remember this workflow for releases.
---

# Versioned Sample Uses and Release Benchmark

Apply when **publishing a new version**, **cutting a release**, or **making version-related changes** to elix-db.

## When to Use

- Before or after publishing a new elix-db version (e.g. v0.2.0, v0.3.0)
- When the user says "publish", "release", "version change", or "new version"
- When adding or changing versioned sample use cases

## What to Remember

**Sample uses are organized by version:** `sample_uses/v0.1.0/`, `sample_uses/v0.2.0/`, etc. Inside each version folder are the same use cases: `01_simple_search`, `02_semantic_faq`, `03_similar_items`, `04_persistence`. Each use case pins `elix_db` to that version in its `mix.exs`.

**On a new version release:**

1. Ensure `sample_uses` has a version folder for the **new** version (e.g. `v0.2.0`) with the same four use cases and `elix_db` pinned to that version.
2. Run the benchmark runner for the new version (e.g. from repo root: run the script that executes each use case in `sample_uses/<version>/`, collects metrics).
3. Compare to the previous version: load the previous version’s report from `sample_uses/reports/`, generate a comparison report (how the new version is better or worse on memory, time, latency, throughput).
4. Update or add report files under `sample_uses/reports/` (e.g. `<version>.json`, `<version>_vs_<prev>.md`).
5. Optionally update CHANGELOG or README with a one-line pointer to the comparison report.

**Metrics that matter for the vector DB:** memory (e.g. `:erlang.memory()`), wall time per use case, latency (mean/p50/p99 for search and upsert), throughput (inserts/s, searches/s). The comparison report should answer: *how is this version compared to the previous one?*

## Workflow Summary

1. Add or update version folder under `sample_uses/<vX.Y.Z>/` with use cases pointing to that elix_db version.
2. Run benchmark for the new version; write `sample_uses/reports/<version>.json` (and optional `.md`).
3. Load previous version report; produce comparison report (e.g. `reports/<version>_vs_<prev>.md`).
4. Remember: this workflow should be run whenever we publish or make version changes so we track memory, time, latency, and other important factors across versions.

## Related

- **debug-verify-benchmark** – for day-to-day changes to vector/store/API (tests, IEx, industry comparison).
- **versioned-sample-uses** – for release/version workflow (sample use cases, version comparison, reports).
