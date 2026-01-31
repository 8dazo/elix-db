---
name: vector-db-storage
description: Storage backends and indexing for vector databases in Elixir. Use when choosing persistence, implementing exact vs approximate k-NN, or integrating pgvector, file, or ETS for vector storage.
---

# Vector DB Storage and Indexing

## Storage Backends

| Backend | Use case | Persistence | Scale |
|---------|----------|-------------|--------|
| **ETS** | Prototype, small index, low latency | No | &lt; ~100k–500k vectors in memory |
| **File** | Simple persistence, no DB | Yes (binary/term) | Same as ETS, plus disk |
| **PostgreSQL + pgvector** | Production, SQL + vectors | Yes | Large; use IVFFlat/HNSW indexes |
| **Qdrant (client)** | Dedicated vector engine | Yes (external) | Very large |

## In-Memory (ETS)

- **:set** table, key = vector id.
- Value: `{id, vector, metadata}`; vector as list or binary.
- No persistence: load from file on GenServer init if needed (see File below).
- **Exact k-NN**: iterate all rows, compute distance, sort, take k. O(n) per query.

## File Persistence

- **On shutdown**: GenServer `terminate/2` or `:gen_server.cast(pid, :persist)` → write ETS contents to file (e.g. `:erlang.term_to_binary(entries)` or custom binary format).
- **On start**: read file, recreate ETS and insert all entries.
- Keep dimension and metadata format in header or config so reload is consistent.

## PostgreSQL + pgvector

Use [pgvector](https://github.com/pgvector/pgvector-elixir) and Ecto for persistent, indexed storage.

- **Schema**: table with `id`, `embedding` (pgvector type), `metadata` (jsonb/map).
- **Index**: create HNSW or IVFFlat index on `embedding` for approximate k-NN.
- **Queries**: use pgvector’s distance operators (`<=>`, `<->`) in raw SQL or Ecto fragments; limit k.

```elixir
# Example: nearest neighbors (cosine distance)
# fragment("embedding <=> ?::vector", ^Nx.to_flat_list(query))
```

- Handles large datasets; persistence and backups via Postgres.

## Exact vs Approximate k-NN

| Method | Accuracy | Speed | When |
|--------|----------|-------|------|
| **Exact** (scan all) | Exact | O(n) per query | Small n (e.g. &lt; 100k), correctness critical |
| **IVFFlat** (pgvector) | Approximate | Fast | Medium/large, good recall with tuning |
| **HNSW** (pgvector) | Approximate | Very fast | Large, high recall |

For in-memory ETS, start with exact k-NN; move to pgvector (or Qdrant) when n grows or persistence is required.

## Design Checklist

- [ ] Persistence requirement clear: none, file, or Postgres
- [ ] If file: define format (term vs binary) and load/save on start/stop
- [ ] If pgvector: add migration for vector column and chosen index (HNSW/IVFFlat)
- [ ] Dimension and distance metric match across insert and search
