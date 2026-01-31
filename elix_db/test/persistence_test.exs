defmodule ElixDb.PersistenceTest do
  use ExUnit.Case, async: false

  test "persist writes collections and points to file" do
    path = Path.join(System.tmp_dir!(), "elix_db_persist_#{System.unique_integer([:positive])}")
    reg = :"reg_#{System.unique_integer([:positive])}"
    store = :"store_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg]})
    start_supervised!({ElixDb.Store, [name: store, registry: reg, data_path: path]})
    ElixDb.CollectionRegistry.create_collection(reg, "coll", 2, :cosine)
    ElixDb.Store.upsert(store, "coll", "id1", [1.0, 0.0], %{x: 1})
    assert :ok = ElixDb.Store.persist(store)

    payload = File.read!(path) |> :erlang.binary_to_term()
    assert %{collections: collections, points: points_map} = payload
    assert length(collections) == 1
    assert hd(collections).name == "coll"
    assert points_map["coll"] == [{"id1", [1.0, 0.0], %{x: 1}}]
  end

  test "load_from_disk on init restores from file" do
    path = Path.join(System.tmp_dir!(), "elix_db_load_#{System.unique_integer([:positive])}")
    payload = %{
      collections: [%ElixDb.Collection{name: "c", dimension: 2, distance_metric: :cosine}],
      points: %{"c" => [{"p1", [1.0, 0.0], %{a: 1}}]}
    }
    File.write!(path, :erlang.term_to_binary(payload))

    reg = :"reg_load_#{System.unique_integer([:positive])}"
    store = :"store_load_#{System.unique_integer([:positive])}"
    start_supervised!({ElixDb.CollectionRegistry, [name: reg]})
    start_supervised!({ElixDb.Store, [name: store, registry: reg, data_path: path]})
    Process.sleep(200)
    assert %{id: "p1", payload: %{a: 1}} = ElixDb.Store.get(store, "c", "p1")
  end
end
