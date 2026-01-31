# Step 7: HTTP API (Optional)

**Status:** Done

## Goal

Expose a minimal **HTTP API** so that collections and points can be managed via REST. Use Plug (or Phoenix if preferred). Endpoints: create collection, list collections, upsert points, search, get, delete. JSON request/response.

## Tasks

- [ ] Add dependency: `plug`, `plug_cowboy` (and `jason` for JSON). Add to `application.ex` so the HTTP server is supervised.
- [ ] Define routes and handlers for: `POST /collections`, `GET /collections`, `GET /collections/:name`, `DELETE /collections/:name`; `PUT /collections/:name/points`, `POST /collections/:name/points/search`, `GET /collections/:name/points/:id`, `DELETE /collections/:name/points/:id`. Optionally `DELETE /collections/:name/points` with filter in body.
- [ ] Map JSON body/query to ElixDb API calls; map results to JSON. Use consistent error responses (e.g. 400 for validation, 404 for missing collection/point).
- [ ] Configurable port (e.g. 4000) via application config.

## Debug

- Start app, use curl or HTTP client: create collection, upsert, search, get, delete. Check status codes and response bodies.

## Verify

- [ ] Integration or request tests: hit each endpoint with valid and invalid input; assert status and body. Optionally run step 1–6 tests to ensure core behavior unchanged.

## Industry Comparison

| Aspect | Qdrant/Milvus | elix-db (this step) | Notes |
|--------|----------------|---------------------|-------|
| API style | REST/gRPC | REST JSON | Subset of Qdrant REST. |
| Endpoints | Collections, points, search | Same | Align naming and payload shape where possible. |

**Efficiency notes:** Single-node; no auth yet. Add rate limiting or auth in future if needed. Document latency overhead of HTTP vs direct GenServer call (step 8).
