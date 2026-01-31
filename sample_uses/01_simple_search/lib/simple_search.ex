defmodule SimpleSearch do
  @moduledoc """
  Minimal “hello world” for ElixDb: create collection, upsert a few 3D points,
  run k-NN search, print results.
  """

  def run do
    coll = "demo"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "p1", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "p2", [0.0, 1.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "p3", [0.0, 0.0, 1.0], %{})

    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, [1.0, 0.0, 0.0], 5)
    IO.puts("k-NN search for [1,0,0] (top 5):")
    Enum.each(results, fn r -> IO.inspect(r, label: nil) end)
  end
end
