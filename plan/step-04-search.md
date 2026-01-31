# Step 4: Search (Exact k-NN)

**Status:** Done

## Goal

Implement **similarity search**: given a collection name and a query vector, return the k nearest points (exact k-NN). Use the collection’s distance metric (cosine or L2). Return list of `{id, score, payload}` (or similar) ordered by similarity (e.g. highest cosine first, or lowest L2 first).

## Tasks

- [ ] Implement `search(collection_name, query_vector, k \\ 10, opts \\ [])`. Opts may include `with_payload: true/false`, `with_vector: true/false` later.
- [ ] Compute distance/similarity for every point in the collection (exact k-NN). Use Nx or Scholar for cosine and L2; ensure consistent with collection metric.
- [ ] Sort by similarity (cosine: descending; L2: ascending) and take top k.
- [ ] Return structured results: e.g. `[%{id: id, score: score, payload: payload}, ...]`. Score is similarity (cosine) or distance (L2) per collection config.

## Debug

- Insert known points (e.g. [1,0,0], [0,1,0], [0,0,1]). Query with [1,0,0]; expect [1,0,0] first for cosine. Vary k and check order.

## Verify

- [ ] Unit tests: known vectors → known ordering; k larger than collection size returns all; empty collection returns empty list.
- [ ] Cosine and L2 metrics both tested; score sign/order correct for each.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| k-NN | Exact or approximate | Exact (scan all) | Approximate (HNSW/IVF) later if needed. |
| Metric | Configurable per collection | cosine / L2 | Match. |
| Latency | Sub-ms to ms at scale | O(n) per query | Acceptable for small/medium n; measure in step 8. |

**Efficiency notes:** Exact k-NN is O(n). For large n, consider approximate index (e.g. pgvector HNSW) in a future step; document recall@k when ground truth exists (step 8).
