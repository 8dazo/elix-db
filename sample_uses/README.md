# sample_uses

Independent Mix projects that use [ElixDb](https://hex.pm/packages/elix_db) from Hex. Samples are organized **by elix_db version** so you can run the same use cases against different releases and compare metrics.

---

## Version folders

| Version | Description |
|---------|-------------|
| [v0.1.0](v0.1.0/) | Use cases pinned to `elix_db ~> 0.1.0` |
| [v0.2.0](v0.2.0/) | Same use cases pinned to `elix_db ~> 0.2.0` |

Inside each version folder you have the same four use cases:

| Folder | Purpose |
|--------|--------|
| 01_simple_search | Minimal “hello world”: create collection, upsert 3D points, k-NN search. |
| 02_semantic_faq | FAQ-style: store questions with mock embeddings, run search and show best match. |
| 03_similar_items | Store item vectors; given one id, get its vector and search for top-k similar. |
| 04_persistence | Create collection, upsert, persist to disk; search after persist. |

---

## How to run (manual)

From repo root, for a given version (e.g. v0.2.0):

```bash
cd sample_uses/v0.2.0/01_simple_search
mix deps.get
mix run -e "SimpleSearch.run"
```

Same pattern for the others: `SemanticFaq.run`, `SimilarItems.run`, `Persistence.run`.

---

## Benchmark and reports

Each use case exposes a fixed workload and `run_bench/0` that writes `bench_result.json` (inserts, searches, wall_us, memory_bytes). A runner script runs all use cases for a version and writes reports.

**Run benchmark for a version** (from `sample_uses`):

```bash
cd sample_uses
elixir script/run_bench.exs v0.1.0
```

**Run and compare to previous version**:

```bash
elixir script/run_bench.exs v0.2.0 v0.1.0
```

This:

1. Runs each use case in `sample_uses/<version>/` (mix deps.get, then mix run -e "Module.run_bench").
2. Writes `reports/<version>.term` and `reports/<version>.json` with per-use-case metrics (wall_us, memory_bytes, inserts, searches).
3. If a previous version report exists (or you pass it as second arg), writes `reports/<version>_vs_<prev>.md` with a comparison table (how the new version compares on time and memory).

**Reports location:** [reports/](reports/) — use these when publishing a new elix_db version to document “how it is good from previous version” (see project skill **versioned-sample-uses**).

---

## Dependency

Each sample’s `mix.exs` pins elix_db to that version folder’s release:

- `v0.1.0/*` → `{:elix_db, "~> 0.1.0"}`
- `v0.2.0/*` → `{:elix_db, "~> 0.2.0"}`

Run `mix deps.get` inside a sample folder to fetch it.
