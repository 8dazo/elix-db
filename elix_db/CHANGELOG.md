# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Search: batch Nx similarity (`Similarity.cosine_batch/2`, `dot_product_batch/2`, `l2_batch/2`) for faster exact k-NN; Store search uses batch APIs
- HTTP: OpenAPI 3.0 spec at `GET /openapi.json`; `priv/openapi.json` documents all endpoints
- Stress tests: `test/stress_test.exs` at 10k vectors (tag `:stress`); run with `mix test test/stress_test.exs` or exclude with `--exclude stress`

## [0.2.0] - 2025-01-31

### Added

- Search: payload filter (`opts[:filter]`) so only points matching the filter are considered for k-NN
- Search: `score_threshold` (cosine/dot_product) and `distance_threshold` (L2) to filter results by score or distance
- Dot product as a third distance metric (`:dot_product`) for normalized vectors
- HTTP: `POST /collections/:name/points/batch` for batch upsert; search body accepts `filter`, `score_threshold`, `distance_threshold`, `with_payload`, `with_vector`
- HTTP: `GET /health` returning status and store/registry reachability
- Metrics wired into Store for all key operations (upsert, upsert_batch, search, get, get_many, delete, delete_many, delete_by_filter, persist)
- Telemetry: `[:elix_db, :store, operation]` events with `duration_us` for all Store operations
- Benchmark script: per-operation mean, p50, p99 (ms) and QPS; optional `--json` output
- Safer persistence: optional `config :elix_db, persist_interval_sec` for periodic auto-save; optional `persist_after_batch` to flush after each batch upsert
- Collection lifecycle: when a collection is deleted via CollectionRegistry (with `store` option), Store drops the corresponding ETS table; `Store.delete_collection/2` API to drop a collection's table directly

### Changed

- CollectionRegistry state structure and init accept optional `:store` option for Store cleanup on collection delete
- Application starts CollectionRegistry with `store: ElixDb.Store` so collection delete clears Store tables

## [0.1.0] - 2025-01-31

### Added

- Collections: create, list, get, delete (dimension, distance metric: cosine / L2)
- Points: upsert, upsert_batch, get, get_many, delete, delete_many, delete_by_filter
- Exact k-NN search (cosine or L2), top-k with optional payload/vector in results
- File persistence (single file, load on startup)
- Optional HTTP API (Plug/Cowboy): collections and points CRUD + search
- Metrics module (operation timings); benchmark script
- Unit tests, property-based tests (StreamData), verification tests (2k vectors, concurrent readers)

[Unreleased]: https://github.com/8dazo/elix-db/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/8dazo/elix-db/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/8dazo/elix-db/releases/tag/v0.1.0
