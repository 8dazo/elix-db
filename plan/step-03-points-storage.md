# Step 3: Points Storage

**Status:** Done

## Goal

Implement **points**: each point has an id, a vector (list of floats, length = collection dimension), and optional payload (metadata map). Support **upsert** (insert or replace by id) per collection. Store points in ETS, one table per collection (or one table with composite key collection+id).

## Tasks

- [ ] Define point representation: `{id, vector, payload}`; id can be string or integer; payload a map.
- [ ] For each collection, maintain an ETS table (or equivalent) for points. Create ETS table when collection is created (step 2) or on first upsert.
- [ ] Implement `upsert(collection_name, id, vector, payload \\ %{})`. Validate vector length matches collection dimension; payload arbitrary map.
- [ ] Implement `upsert_batch(collection_name, points)` for multiple points (list of `{id, vector, payload}`).
- [ ] Ensure id is unique per collection (upsert overwrites).

## Debug

- Create a collection (e.g. dimension 3, cosine). Upsert a few points. Inspect ETS or internal state. Upsert same id again and confirm overwrite.

## Verify

- [ ] Tests: upsert single and batch; vector length mismatch returns error; duplicate id overwrites.
- [ ] Same collection enforces same dimension across upserts.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Point model | id, vector, payload | id, vector, payload | Aligned. |
| Upsert | Replace by id | Replace by id | Same. |
| Storage | Distributed / WAL | ETS in-memory | Persistence in step 6. |

**Efficiency notes:** Batch upsert reduces per-point overhead; ETS gives O(1) lookup by id. Consider batching in API layer for large imports.
