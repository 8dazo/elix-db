# sample_uses

Independent Mix projects that use [ElixDb](https://hex.pm/packages/elix_db) from Hex. Each subfolder is a **standalone** project with no dependency on any other sample—only on the `elix_db` package.

To add a new use case: create a new folder (e.g. `05_...`) with its own `mix.exs` and code, then add one row to the table below.

---

## List of samples

| Folder | Purpose | How to run |
|--------|--------|------------|
| [01_simple_search](01_simple_search/) | Minimal “hello world”: create collection, upsert a few 3D points, run k-NN search, print results. | `cd sample_uses/01_simple_search && mix deps.get && mix run -e "SimpleSearch.run"` |
| [02_semantic_faq](02_semantic_faq/) | FAQ-style demo: store questions with mock embedding vectors and payloads, run one search and show best match. | `cd sample_uses/02_semantic_faq && mix deps.get && mix run -e "SemanticFaq.run"` |
| [03_similar_items](03_similar_items/) | “Similar items”: store item vectors, then given one id, get its vector and run search for top-k similar (excluding self). | `cd sample_uses/03_similar_items && mix deps.get && mix run -e "SimilarItems.run"` |
| [04_persistence](04_persistence/) | Persistence demo: create collection, upsert points, persist to disk; after restart the store loads and search still works. | `cd sample_uses/04_persistence && mix deps.get && mix run -e "Persistence.run"` |

---

## Dependency

Each sample depends on `elix_db` from Hex in its `mix.exs`:

```elixir
{:elix_db, "~> 0.1.0"}
```

Run `mix deps.get` inside a sample folder to fetch it.
