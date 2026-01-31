---
name: elixir-vector-patterns
description: Elixir patterns for vector storage and similarity search. Use when implementing GenServer-based vector store, ETS index, Nx/Scholar distance math, or supervision for a vector DB in Elixir.
---

# Elixir Vector DB Patterns

## In-Memory Store with GenServer + ETS

Use a GenServer to own an ETS table keyed by id; store `{id, vector, metadata}`. Vectors as list or Nx tensor (serialize to binary for ETS if needed).

```elixir
defmodule ElixDb.VectorStore do
  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    dimension = Keyword.fetch!(opts, :dimension)
    GenServer.start_link(__MODULE__, {name, dimension}, name: name)
  end

  def init({name, dimension}) do
    table = :ets.new(name, [:set, :protected, :named_table])
    {:ok, %{table: table, dimension: dimension}}
  end

  def insert(server, id, vector, metadata \\ %{}) do
    GenServer.call(server, {:insert, id, vector, metadata})
  end

  def search(server, query_vector, k \\ 10) do
    GenServer.call(server, {:search, query_vector, k})
  end

  def handle_call({:insert, id, vector, metadata}, _from, state) do
    :ets.insert(state.table, {id, vector, metadata})
    {:reply, :ok, state}
  end

  def handle_call({:search, query_vector, k}, _from, state) do
    results = do_knn(state.table, query_vector, k)
    {:reply, results, state}
  end

  defp do_knn(table, query_vector, k) do
    # Collect all, compute distances, sort, take k (see distance section)
    :ets.tab2list(table)
    |> Enum.map(fn {id, vec, meta} -> {id, cosine_similarity(query_vector, vec), meta} end)
    |> Enum.sort_by(fn {_id, sim, _} -> -sim end, :asc)
    |> Enum.take(k)
  end
end
```

## Distance and Similarity (Nx / Scholar)

**Cosine similarity** (for normalized vectors, dot product = cosine):

```elixir
# Nx: ensure vectors are 1-D tensors
def cosine_similarity(a, b) do
  a = Nx.tensor(a)
  b = Nx.tensor(b)
  Nx.divide(Nx.dot(a, b), Nx.multiply(Nx.Linalg.norm(a), Nx.Linalg.norm(b)))
  |> Nx.squeeze()
  |> Nx.to_number()
end
```

**Scholar** (pairwise cosine distance = 1 - similarity):

```elixir
# Scholar.Metrics.Distance.cosine/3 returns distance; similarity = 1 - distance
# pairwise_cosine for many vectors at once (batch)
```

**L2 (Euclidean) distance**:

```elixir
def l2_distance(a, b) do
  a = Nx.tensor(a)
  b = Nx.tensor(b)
  Nx.Linalg.norm(Nx.subtract(a, b)) |> Nx.squeeze() |> Nx.to_number()
end
```

Use one metric consistently for insert and search.

## Vector Representation in ETS

- Store as **list of floats** for simplicity: `[0.1, -0.2, ...]`
- Or **binary** from `Nx.to_flat_list(vec) |> :erlang.list_to_binary()` and decode when reading (saves memory for large tables)
- Validate dimension on insert against store config.

## Supervision Tree

Run the vector store under your application so it survives restarts and is started in order.

```elixir
# lib/elix_db/application.ex
children = [
  {ElixDb.VectorStore, name: ElixDb.VectorStore, dimension: 1536}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

## Concurrency

- **GenServer** serializes all insert/search; good for correctness, single process.
- For read-heavy scale: consider multiple ETS tables (shard by id hash) or move to pgvector/Qdrant.
- Prefer **`:protected`** ETS so other processes can read (e.g. `:ets.lookup`) while GenServer handles writes if you split read path later.

## Checklist

- [ ] Dimension validated on insert
- [ ] One distance metric used everywhere
- [ ] Vectors normalized if using cosine (optional but often done at embedding step)
- [ ] Store registered in application supervision
