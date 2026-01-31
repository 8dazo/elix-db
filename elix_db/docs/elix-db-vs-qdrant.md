# elix-db vs Qdrant: API & Concepts Comparison

Side-by-side comparison of **points**, **upsert**, **get**, **delete**, **search**, and **collections** so you can see what elix-db pulls from Qdrant and where it differs.

---

## Concepts

| Concept | Qdrant | elix-db |
|--------|--------|---------|
| **Collection** | Named container; has vector size & distance metric. | Same: `name`, `dimension`, `distance_metric` (cosine, dot_product, l2). |
| **Point** | `id` + `vector` + optional `payload`. ID: integer or UUID. | Same: `{id, vector, payload}`. ID: any term (string, int, etc.). |
| **Payload** | Arbitrary JSON key-value. | Same: map of key-value (stored with point). |
| **Vector** | List of numbers; dimension fixed per collection. | Same: list of floats; dimension validated at upsert. |

---

## Collections

| Operation | Qdrant | elix-db |
|----------|--------|---------|
| **Create** | `PUT /collections/:name` with config (size, distance, etc.). | `POST /collections` body: `name`, `dimension`, `distance_metric`. |
| **List** | `GET /collections`. | `GET /collections`. |
| **Get one** | `GET /collections/:name`. | `GET /collections/:name`. |
| **Delete** | `DELETE /collections/:name`. | `DELETE /collections/:name`. |

elix-db mirrors Qdrant’s collection CRUD; create uses POST + JSON body instead of PUT.

---

## Points: Upsert

| Operation | Qdrant | elix-db |
|----------|--------|---------|
| **Upsert (batch)** | `PUT /collections/:name/points` — body: `points: [{ id, vector, payload? }]`. Same ID ⇒ overwrite. | `POST /collections/:name/points/batch` — body: `points: [{ id, vector, payload? }]`. Same semantics. |
| **Upsert (single)** | Same endpoint; one point in array. | `PUT /collections/:name/points` — body: `id`, `vector`, `payload?`. |
| **Wait / ordering** | Query params: `wait`, `ordering` (weak/medium/strong). | No `wait`/`ordering`; operations are synchronous. |

So: **point structure and overwrite-by-id match Qdrant**; elix-db uses a dedicated single-point PUT and has no ordering/wait options.

---

## Points: Get (retrieve by ID)

| Operation | Qdrant | elix-db |
|----------|--------|---------|
| **Get many** | `POST /collections/:name/points` — body: `ids: [id1, id2, ...]`, optional `with_payload`, `with_vector`. | Not on HTTP. Store has `get_many/4`. |
| **Get one** | Same; one id in `ids`. | `GET /collections/:name/points/:id` — returns one point (id, vector, payload). |

elix-db exposes **get one** via REST; **get many** exists only in `ElixDb.Store.get_many/4`, not in the HTTP API.

---

## Points: Delete

| Operation | Qdrant | elix-db |
|----------|--------|---------|
| **Delete by IDs** | `POST /collections/:name/points/delete` — body: `points: [id1, id2, ...]`. | Single: `DELETE /collections/:name/points/:id`. Many: `Store.delete_many/3` only (no HTTP). |
| **Delete by filter** | Same endpoint — body: `filter: { must: [ { key, match: { value } } ] }`. | `Store.delete_by_filter/3` only (no HTTP). |

So: **single-point delete** is in the API; **delete many by IDs** and **delete by filter** exist in the Store but are **not** exposed on the HTTP router.

---

## Points: Search (k-NN)

| Operation | Qdrant | elix-db |
|----------|--------|---------|
| **Vector search** | `POST /collections/:name/points/search` — body: `vector`, `limit`, `with_payload`, `with_vector`, `filter`, `score_threshold`, etc. | `POST /collections/:name/points/search` — body: `vector`, `k` (default 10), `filter`, `score_threshold`, `distance_threshold`, `with_payload`, `with_vector`. |
| **Filter** | Nested `must`/`should`/`must_not` with `key`/`match`. | Flat map: payload key/value pairs (all must match). |
| **Score/distance** | `score_threshold` for similarity; distance type per collection. | Same idea: `score_threshold` (cosine/dot_product), `distance_threshold` (L2). |

Search **concept and options** are aligned; elix-db uses a simpler flat filter and `k` instead of `limit`.

---

## Summary: What elix-db “pulls” from Qdrant

- **Same core model:** collections, points (id + vector + payload), overwrite on upsert by id.
- **Same operations:** create/list/get/delete collections; upsert points (single + batch); get point(s); delete point(s); k-NN search with filter and score/distance thresholds.
- **Same distance metrics:** cosine, dot product, L2.

---

## Gaps: Where they differ

| Area | Qdrant | elix-db |
|------|--------|---------|
| **Point ID type** | uint64 or UUID. | Any term (string, int, etc.). |
| **Get many (HTTP)** | `POST .../points` with `ids: [...]`. | No HTTP endpoint; only `Store.get_many/4`. |
| **Delete many (HTTP)** | `POST .../points/delete` with `points: [ids]` or `filter`. | Only `DELETE .../points/:id`. Store has `delete_many`, `delete_by_filter`. |
| **Filter expressiveness** | Rich: must/should/must_not, range, match, etc. | Simple: flat payload key-value (all must match). |
| **Delete payload keys** | `POST .../points/payload/delete` (remove keys from points). | Not implemented. |
| **Wait / ordering** | `wait`, `ordering` on write/delete. | Synchronous only; no params. |
| **Index** | HNSW, etc.; incremental. | Optional DAZO (graph + sketches); rebuild after bulk changes. |
| **Scale** | Single-node to distributed; 1M+ vectors, sub-ms. | Single-node; best for small/medium (e.g. &lt; 50k–100k); exact or DAZO. |

---

## Quick reference: HTTP endpoints

| Intent | Qdrant | elix-db |
|--------|--------|---------|
| Create collection | `PUT /collections/:name` | `POST /collections` |
| List collections | `GET /collections` | `GET /collections` |
| Get collection | `GET /collections/:name` | `GET /collections/:name` |
| Delete collection | `DELETE /collections/:name` | `DELETE /collections/:name` |
| Upsert points (batch) | `PUT /collections/:name/points` | `POST /collections/:name/points/batch` |
| Upsert one point | `PUT /collections/:name/points` (1 point) | `PUT /collections/:name/points` |
| Get point(s) | `POST /collections/:name/points` (body: `ids`) | `GET /collections/:name/points/:id` (single only) |
| Delete point(s) | `POST /collections/:name/points/delete` (ids or filter) | `DELETE /collections/:name/points/:id` (single only) |
| Search | `POST /collections/:name/points/search` | `POST /collections/:name/points/search` |

So: **points, upsert, get-one, delete-one, and search** are the parts that line up the most; **get-many** and **delete-many/delete-by-filter** are implemented in the Store but not yet on the HTTP API.
