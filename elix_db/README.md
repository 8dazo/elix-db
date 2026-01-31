# ElixDb (package)

Elixir vector database: collections, points, exact k-NN search (cosine/L2), persistence, HTTP API.

See the [project README](../README.md) for quick start, IEx examples, HTTP API, and benchmarks.

## Installation (local)

From this directory:

```bash
mix deps.get
mix test
iex -S mix
```

## Hex (when published)

```elixir
def deps do
  [{:elix_db, "~> 0.1.0"}]
end
```

## Docs

- Benchmarks and production notes: [docs/benchmarks.md](docs/benchmarks.md)
