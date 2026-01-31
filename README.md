# elix-db

[![Hex.pm](https://img.shields.io/hexpm/v/elix_db.svg)](https://hex.pm/packages/elix_db)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/elix_db)
[![GitHub stars](https://img.shields.io/github/stars/8dazo/elix-db.svg)](https://github.com/8dazo/elix-db)

A small **vector database** written in Elixir: collections, points (upsert / get / delete), **exact k-NN search** (cosine or L2), file persistence, and an optional HTTP API.

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

- **Collections** – Create named collections with fixed dimension and distance metric (`cosine` or `l2`).
- **Points** – Upsert (single or batch), get, get_many, delete, delete_by_filter. Optional payload (map) per point.
- **Search** – Exact k-NN similarity search with cosine or L2; returns top-k points with scores.
- **Persistence** – Single-file save/load on disk; load on startup.
- **HTTP API** – Optional Plug/Cowboy server for REST-style access (create collection, upsert, search, get, delete).
- **Tests** – Unit tests, property-based tests (StreamData), and verification tests at 2k vectors and concurrent readers.

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

# Search
{:ok, results} = ElixDb.Store.search(ElixDb.Store, "my_coll", [1.0, 0.0, 0.0], 5)
# => [%{id: "p1", score: 1.0, payload: ...}, ...]

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
```

Reports insert/search latency and QPS (default: 1000 vectors, dim 64, k=10). See `elix_db/docs/benchmarks.md` for numbers and comparison notes.

## Project layout

| Path | Description |
|------|-------------|
| `elix_db/` | Mix application (lib, test, script, docs) |
| `elix_db/lib/elix_db/` | Core modules: Application, CollectionRegistry, Store, Similarity, HttpRouter, Metrics |
| `plan/` | Step-by-step build plan (scaffold → collections → points → search → get/delete → persistence → HTTP → metrics) |

## When to use

- **Good for:** Small to medium vector sets (e.g. &lt; 50k–100k vectors), prototypes, internal tools, exact k-NN.
- **Not for:** Millions of vectors with sub-ms search (no approximate index; search is O(n)). For that, consider pgvector, Qdrant, or Milvus.

---

## License

MIT – see [elix_db/LICENSE](elix_db/LICENSE).
