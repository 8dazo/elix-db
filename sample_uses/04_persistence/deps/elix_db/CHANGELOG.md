# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-31

### Added

- Collections: create, list, get, delete (dimension, distance metric: cosine / L2)
- Points: upsert, upsert_batch, get, get_many, delete, delete_many, delete_by_filter
- Exact k-NN search (cosine or L2), top-k with optional payload/vector in results
- File persistence (single file, load on startup)
- Optional HTTP API (Plug/Cowboy): collections and points CRUD + search
- Metrics module (operation timings); benchmark script
- Unit tests, property-based tests (StreamData), verification tests (2k vectors, concurrent readers)

[Unreleased]: https://github.com/8dazo/elix-db/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/8dazo/elix-db/releases/tag/v0.1.0
