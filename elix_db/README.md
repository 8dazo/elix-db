# ElixDb

[![Hex.pm](https://img.shields.io/hexpm/v/elix_db.svg)](https://hex.pm/packages/elix_db)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/elix_db)
[![GitHub stars](https://img.shields.io/github/stars/8dazo/elix-db.svg)](https://github.com/8dazo/elix-db)

Elixir vector database: collections, points (upsert/get/delete), **exact k-NN** (cosine, L2, dot product), optional **DAZO index** with **HNSW-style multi-layer graph** (Qdrant/Milvus-like) and **IVF coarse quantizer**, **Nx batch re-rank**, file persistence, and optional HTTP API.

---

## Links

- **GitHub:** [github.com/8dazo/elix-db](https://github.com/8dazo/elix-db)
- **Hex:** [hex.pm/packages/elix_db](https://hex.pm/packages/elix_db)
- **Docs:** [hexdocs.pm/elix_db](https://hexdocs.pm/elix_db)

---

## Installation

Add `elix_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:elix_db, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get`.

Documentation: [https://hexdocs.pm/elix_db](https://hexdocs.pm/elix_db).

---

## Quick start

```bash
mix deps.get
mix test
iex -S mix
```

```elixir
# Create collection (dim 3, cosine)
ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, "my_coll", 3, :cosine)

# Upsert and search
ElixDb.Store.upsert(ElixDb.Store, "my_coll", "p1", [1.0, 0.0, 0.0], %{})
{:ok, results} = ElixDb.Store.search(ElixDb.Store, "my_coll", [1.0, 0.0, 0.0], 5)

# Build DAZO index for faster search (HNSW 500–5k vectors, IVF ≥5k; Nx batch re-rank)
ElixDb.DazoIndex.build(ElixDb.DazoIndex, ElixDb.Store, "my_coll", registry: ElixDb.CollectionRegistry)
# Options: full_scan_threshold (500), coarse_threshold (5k), m, ef_construct, ef
# Force brute-force: Store.search(store, "my_coll", vector, k, brute_force: true)
```

See the [project README](https://github.com/8dazo/elix-db) for production status, HNSW/IVF details, HTTP API, benchmarks (`script/full_bench.exs --dazo`), and full docs.

---

## License

MIT – see [LICENSE](https://github.com/8dazo/elix-db/blob/main/elix_db/LICENSE).
