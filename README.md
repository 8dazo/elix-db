# elix-db

[![Hex.pm](https://img.shields.io/hexpm/v/elix_db.svg)](https://hex.pm/packages/elix_db)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/elix_db)
[![GitHub stars](https://img.shields.io/github/stars/8dazo/elix-db.svg)](https://github.com/8dazo/elix-db)

A small **vector database** written in Elixir: collections, points (upsert / get / delete), **exact k-NN search** (cosine, L2, or dot product), optional **DAZO index** with **HNSW-style multi-layer graph** (Qdrant/Milvus-like) and **IVF coarse quantizer** for faster approximate search, **Nx batch re-rank**, file persistence, and an optional HTTP API.

---

## Links

- **GitHub:** [github.com/8dazo/elix-db](https://github.com/8dazo/elix-db)
- **Hex:** [hex.pm/packages/elix_db](https://hex.pm/packages/elix_db)
- **Docs:** [hexdocs.pm/elix_db](https://hexdocs.pm/elix_db)

---

## Install

Add `elix_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elix_db, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get`. Full API docs: [hexdocs.pm/elix_db](https://hexdocs.pm/elix_db).

---

## Features

- **Collections** – Create named collections with fixed dimension and distance metric (`cosine`, `l2`, or `dot_product`).
- **Points** – Upsert (single or batch), get, get_many, delete, delete_by_filter. Optional payload (map) per point.
- **Search** – Exact k-NN (brute-force) or **DAZO index**:
  - **full_scan_threshold** (default 500): below this many vectors, no index is built; search is brute-force (Qdrant-style).
  - **HNSW-style multi-layer graph** (500–5k vectors): Qdrant/Milvus-like algorithm (M, ef_construct, ef); entry → descend → search_on_level; full-vector distance.
  - **IVF coarse quantizer** (≥5k vectors): k-means on 32-bit sketches → nprobe buckets → re-rank.
  - **Nx batch re-rank** for all DAZO paths; filter, score/distance thresholds, `ef`, `nprobe`.
- **Persistence** – Single-file save/load for Store and DAZO index; load on startup.
- **HTTP API** – Optional Plug/Cowboy server for REST-style access (create collection, upsert, search, get, delete).
- **Tests** – Unit tests, property-based tests (StreamData), DAZO tests (EAB, Graph, HnswGraph, CoarseQuantizer, DazoIndex), verification and stress tests (10k vectors).

## Requirements

- Elixir ~> 1.19
- Mix project in `elix_db/`

## Quick start (from source)

```bash
cd elix_db
mix deps.get
mix test
```

### IEx

```bash
cd elix_db
iex -S mix
```

```elixir
# Create a collection (dimension 3, cosine similarity)
ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, "my_coll", 3, :cosine)

# Upsert points
ElixDb.Store.upsert(ElixDb.Store, "my_coll", "p1", [1.0, 0.0, 0.0], %{label: "x"})
ElixDb.Store.upsert(ElixDb.Store, "my_coll", "p2", [0.0, 1.0, 0.0], %{})

# Search: uses DAZO index by default when one exists; otherwise brute-force
{:ok, results} = ElixDb.Store.search(ElixDb.Store, "my_coll", [1.0, 0.0, 0.0], 5)
# => [%{id: "p1", score: 1.0, payload: ...}, ...]

# Build DAZO index for faster search (HNSW for 500–5k vectors, IVF for larger; Nx batch re-rank)
ElixDb.DazoIndex.build(ElixDb.DazoIndex, ElixDb.Store, "my_coll", registry: ElixDb.CollectionRegistry)
# Options: full_scan_threshold (default 500), coarse_threshold (5k), m, ef_construct, ef
# To force brute-force: Store.search(store, "my_coll", vector, k, brute_force: true)

# Get / delete
ElixDb.Store.get(ElixDb.Store, "my_coll", "p1")
ElixDb.Store.delete(ElixDb.Store, "my_coll", "p1")
```

### HTTP API

Start the app with the HTTP router mounted (see `elix_db/lib/elix_db/application.ex`). Endpoints include:

- `POST /collections` – create collection (body: `name`, `dimension`, `distance_metric`)
- `GET /collections` – list collections
- `PUT /collections/:name/points` – upsert point (body: `id`, `vector`, optional `payload`)
- `POST /collections/:name/points/search` – k-NN search (body: `vector`, optional `k`)
- `GET /collections/:name/points/:id` – get point
- `DELETE /collections/:name/points/:id` – delete point

### Benchmark

```bash
cd elix_db
mix run script/bench.exs
mix run script/full_bench.exs --dazo --n 500   # full functionality + DAZO (HNSW/IVF) + comparison table
```

Reports insert/search latency and QPS (default: 1000 vectors, dim 64, k=10). With `--dazo`, builds a DAZO index (HNSW or IVF by n) and reports search with Nx batch re-rank. See `elix_db/docs/benchmarks.md` for numbers and comparison vs Qdrant/Milvus.

## Project layout

| Path | Description |
|------|-------------|
| `elix_db/` | Mix application (lib, test, script, docs) |
| `elix_db/lib/elix_db/` | Core: Application, CollectionRegistry, Store, Similarity, HttpRouter, Metrics; **DazoIndex**; **dazo/** (EAB, **HnswGraph**, Graph, CoarseQuantizer, PredicateMask) |
| `DAZO.md` | DAZO design: full_scan_threshold, HNSW (M/ef_construct/ef), IVF, Nx batch re-rank; elix-db integration |
| `elix_db/docs/` | benchmarks.md, performance.md, elix-db-vs-qdrant.md |
| `plan/` | Step-by-step build plan |
| `sample_uses/` | Versioned sample use cases; see sample_uses/README.md |

## Production status and limitations

**Production readiness:** Suitable for **small to medium** workloads (e.g. &lt; 50k–100k vectors per collection), prototypes, and internal tools. Not aimed at billion-scale or sub-ms SLA at very large n.

**Limitations:**

- **Scale:** If n ≤ `full_scan_threshold` (500), no index is built and search is O(n) brute-force. With DAZO: HNSW (500–5k vectors) or IVF (≥5k); index must be **rebuilt** after bulk changes (no incremental update).
- **DAZO:** HNSW uses full-vector distance (Qdrant/Milvus-like); IVF uses EAB 32-bit sketches; legacy graph uses predicate masks (8-bit). Filter config at build time for graph path only.
- **Persistence:** Single-file binary term for Store and DAZO index; no WAL, no point-in-time recovery. Optional `persist_interval_sec` and `persist_after_batch` reduce data-loss window.
- **Operational:** Single-node only; HTTP API has no auth or rate limiting; metrics and Telemetry exist but no built-in dashboards.

**When to use**

- **Good for:** Small/medium vector sets, exact or DAZO-accelerated k-NN (HNSW/IVF), filtered search, correctness-focused workloads.
- **Not for:** Millions of vectors with sub-ms SLA, incremental index updates, or distributed deployment. For that, use pgvector, Qdrant, or Milvus.

---

## License

MIT – see [elix_db/LICENSE](elix_db/LICENSE).
