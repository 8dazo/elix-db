defmodule SemanticFaq do
  @moduledoc """
  FAQ-style demo: store a few “questions” with mock embedding vectors and
  payloads (q/a), run one search and show best match.
  """

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
end
