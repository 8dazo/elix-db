defmodule SimilarItems do
  @moduledoc """
  “Similar items”: store item vectors by id, then given one id, get its vector,
  run search, return top-k similar (excluding self).
  """

  def run do
    coll = "items"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "item_a", [1.0, 0.0, 0.0], %{name: "A"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_b", [0.9, 0.1, 0.0], %{name: "B"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_c", [0.0, 1.0, 0.0], %{name: "C"})
    ElixDb.Store.upsert(ElixDb.Store, coll, "item_d", [0.0, 0.0, 1.0], %{name: "D"})

    # Find items similar to "item_a"
    target_id = "item_a"
    point = ElixDb.Store.get(ElixDb.Store, coll, target_id, with_vector: true)
    vector = point.vector
    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, vector, 4)

    # Exclude self (item_a)
    similar = Enum.reject(results, fn r -> r.id == target_id end)
    IO.puts("Items similar to #{target_id}:")
    Enum.each(similar, fn r -> IO.inspect(r, label: nil) end)
  end
end
