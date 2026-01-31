---
name: vector-db-elixir
description: Design and implement a vector database in Elixir. Use when building embedding storage, similarity search, k-NN retrieval, or when the user mentions vector DB, embeddings, or semantic search in Elixir.
---

# Vector Database in Elixir

## Scope

A vector DB stores high-dimensional vectors (embeddings) and supports **similarity search**: find the k nearest vectors to a query vector by distance (cosine, Euclidean, dot product).

## Core Operations

| Operation | Description |
|-----------|-------------|
| **insert** | Add vector(s) with optional metadata (id, payload) |
| **search** | Query vector → return k nearest vectors (by similarity) |
| **delete** | Remove by id or filter |
| **get** | Fetch by id (optional) |

## Implementation Workflow

1. **Choose storage backend**
   - In-memory: ETS (fast, no persistence)
   - Persistent: file (binary/term), or PostgreSQL with [pgvector](https://github.com/pgvector/pgvector-elixir)
   - External: [Qdrant](https://hexdocs.pm/qdrant) client

2. **Choose distance metric**
   - Cosine similarity (often for normalized embeddings)
   - Euclidean (L2)
   - Dot product (when vectors already normalized, equivalent to cosine)

3. **Implement or wire**
   - **Exact k-NN**: compute distance to every vector (fine for &lt; ~100k vectors in memory)
   - **Approximate**: use pgvector indexes (IVFFlat, HNSW) or external engine for scale

4. **Expose API**
   - GenServer or dedicated context module: `insert/2`, `search/2`, `delete/1`
   - Optional HTTP/Web API on top

## Elixir Stack (Typical)

- **Nx** or **Scholar** for vector math (cosine, L2, dot product)
- **GenServer** + **ETS** or **:array** for in-memory index
- **pgvector** + Ecto for persistent, indexed storage
- **Application** supervision tree to start the vector store process

## Design Checklist

- [ ] Vector dimension fixed per collection (e.g. 1536 for OpenAI embeddings)
- [ ] Ids unique; support upsert by id if required
- [ ] Metadata/payload stored with vector for filtering or display
- [ ] Distance metric consistent for insert and search
- [ ] Persistence strategy (none, file, DB) decided and implemented

## Additional Resources

- For Elixir patterns (GenServer, ETS, Nx), see [elixir-vector-patterns](../elixir-vector-patterns/SKILL.md)
- For storage and indexing options, see [vector-db-storage](../vector-db-storage/SKILL.md)
