# Step 2: Collections

**Status:** Done

## Goal

Introduce the **collection** abstraction: a named container with a fixed vector dimension and distance metric (cosine or L2). No points yet—only create/list/delete collections and store collection config (e.g. in ETS or a GenServer state).

## Tasks

- [ ] Define a struct or schema for a collection: `name`, `dimension`, `distance_metric` (e.g. `:cosine` | `:l2`).
- [ ] Implement a GenServer or ETS-backed registry that stores collection configs keyed by name.
- [ ] API: `create_collection(name, dimension, metric)`, `list_collections()`, `get_collection(name)`, `delete_collection(name)`.
- [ ] Validate: dimension positive integer; metric one of allowed values; name unique.
- [ ] Start the collections registry under `ElixDb.Application` supervision tree.

## Debug

- In IEx: create a collection, list it, get it, delete it. Try invalid inputs and assert errors.

## Verify

- [ ] Unit tests: create/list/get/delete collections; invalid dimension or metric returns error.
- [ ] Restart IEx; collections are in-memory only (no persistence yet)—after restart they are empty.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Collection config | dimension, metric, optional params | dimension, metric | Match core fields. |
| API | REST/gRPC create collection | GenServer calls | Same semantics; HTTP in step 7. |

**Efficiency notes:** Registry lookup O(1) by name; minimal memory per collection until points added.
