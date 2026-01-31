# Step 5: Get and Delete

**Status:** Done

## Goal

Support **get by id(s)** and **delete**. Get returns one or more points by id (optionally with vector). Delete removes points by id or by payload filter (e.g. key-value match).

## Tasks

- [ ] Implement `get(collection_name, id)` and `get_many(collection_name, ids)`. Return point(s) or nil/empty; option to include/exclude vector and payload.
- [ ] Implement `delete(collection_name, id)` and `delete_many(collection_name, ids)`.
- [ ] Implement `delete_by_filter(collection_name, filter)` where filter is a map of payload key-value conditions (e.g. `%{ "status" => "archived" }`). All points matching all conditions are removed.
- [ ] After delete, search and get must not return deleted points.

## Debug

- Upsert points, get by id, get_many. Delete one, confirm get returns nil and search excludes it. Test delete_by_filter with payload conditions.

## Verify

- [ ] Tests: get/get_many return correct points or nil; delete removes points; delete_by_filter removes only matching points; search and get reflect deletions.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| Get by id | Supported | Supported | Same. |
| Delete by id | Supported | Supported | Same. |
| Delete by filter | Payload/condition filter | Payload key-value match | Basic filter; extend to nested/range later if needed. |

**Efficiency notes:** Get/delete by id O(1) with ETS; delete_by_filter O(n) scan. For large deletes by filter, consider batching or async in future.
