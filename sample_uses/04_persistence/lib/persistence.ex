defmodule Persistence do
  @moduledoc """
  Persistence demo: create collection, upsert points, call ElixDb.Store.persist/1.
  After restart the store loads from disk and search still works.
  """

  def run do
    coll = "persisted"
    ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, coll, 3, :cosine)

    ElixDb.Store.upsert(ElixDb.Store, coll, "x", [1.0, 0.0, 0.0], %{})
    ElixDb.Store.upsert(ElixDb.Store, coll, "y", [0.0, 1.0, 0.0], %{})

    ElixDb.Store.persist(ElixDb.Store)
    IO.puts("Persisted to disk (data.elix_db).")

    {:ok, results} = ElixDb.Store.search(ElixDb.Store, coll, [1.0, 0.0, 0.0], 5)
    IO.puts("Search after persist: #{length(results)} result(s).")
    Enum.each(results, fn r -> IO.inspect(r, label: nil) end)

    IO.puts("\nTo see load-after-restart: stop this process and run again;")
    IO.puts("ElixDb loads from disk on startup, so the same collection and points will be available.")
  end
end
