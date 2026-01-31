defmodule SemanticFaq do
  @moduledoc """
  FAQ-style demo: store a few “questions” with mock embedding vectors and
  payloads (q/a), run one search and show best match.
  """

  @query_list [
    [0.9, 0.1, 0.0, 0.0],
    [0.0, 0.9, 0.1, 0.0],
    [0.0, 0.0, 0.9, 0.1],
    [0.5, 0.5, 0.0, 0.0],
    [0.3, 0.3, 0.3, 0.1]
  ]

  def run do
    coll = "faq"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 4, :cosine)

    # Mock embeddings: each FAQ entry has a 4D vector; query vector picks nearest.
    ElixDb.Store.upsert(ElixDb.Store, coll, "faq1", [1.0, 0.0, 0.0, 0.0], %{
      q: "How do I install ElixDb?",
      a: "Add {:elix_db, \"~> 0.1.0\"} to deps and run mix deps.get."
    })
    ElixDb.Store.upsert(ElixDb.Store, coll, "faq2", [0.0, 1.0, 0.0, 0.0], %{
      q: "What distance metrics are supported?",
      a: "Cosine and L2."
    })
    ElixDb.Store.upsert(ElixDb.Store, coll, "faq3", [0.0, 0.0, 1.0, 0.0], %{
      q: "How do I run a k-NN search?",
      a: "Use ElixDb.Store.search(ElixDb.Store, collection, query_vector, k)."
    })

    # Query: vector close to “install” topic (first dimension)
    query = [0.9, 0.1, 0.0, 0.0]
    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, query, 3)
    best = List.first(results)
    IO.puts("Best match for query [0.9, 0.1, 0, 0]:")
    IO.puts("  Q: #{best.payload["q"] || best.payload[:q]}")
    IO.puts("  A: #{best.payload["a"] || best.payload[:a]}")
    IO.puts("  score: #{best.score}")
  end

  @doc """
  Runs a fixed workload: 3 FAQ inserts, then 5 searches from @query_list.
  Writes bench_result.json for the benchmark runner.
  """
  def run_bench do
    mem_before = :erlang.memory(:total)
    coll = "faq_bench"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 4, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "faq1", [1.0, 0.0, 0.0, 0.0], %{q: "Q1", a: "A1"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "faq2", [0.0, 1.0, 0.0, 0.0], %{q: "Q2", a: "A2"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "faq3", [0.0, 0.0, 1.0, 0.0], %{q: "Q3", a: "A3"})

    {wall_us, _} = :timer.tc(fn ->
      for q <- @query_list do
        ElixDb.Store.search(ElixDb.Store, coll, q, 3)
      end
    end)

    mem_after = :erlang.memory(:total)
    result = %{
      inserts: 3,
      searches: length(@query_list),
      wall_us: wall_us,
      memory_bytes: mem_after - mem_before
    }
    File.write!("bench_result.json", encode_bench_result(result))
    result
  end

  defp encode_bench_result(m) do
    ~s|{"inserts":#{m.inserts},"searches":#{m.searches},"wall_us":#{m.wall_us},"memory_bytes":#{m.memory_bytes}}|
  end
end
