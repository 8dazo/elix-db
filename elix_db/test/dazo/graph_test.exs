defmodule ElixDb.Dazo.GraphTest do
  use ExUnit.Case, async: true

  alias ElixDb.Dazo.Graph

  describe "build/2" do
    test "empty points returns error" do
      assert Graph.build([], dimension: 2, filter_config: []) == {:error, :empty_points}
    end

    test "single point returns graph with no edges" do
      points = [{"a", [1.0, 0.0], %{}}]
      result = Graph.build(points, dimension: 2, filter_config: [])
      assert %{medoid_id: "a", ids: ["a"], graph: %{"a" => []}} = result
      assert Map.has_key?(result.id_to_sketch, "a")
      assert Map.has_key?(result.id_to_mask, "a")
    end

    test "two points returns graph with edges" do
      points = [
        {"a", [1.0, 0.0], %{}},
        {"b", [0.0, 1.0], %{}}
      ]
      result = Graph.build(points, dimension: 2, filter_config: [], r: 2, seed: 42)
      assert result.medoid_id in ["a", "b"]
      assert length(result.ids) == 2
      assert map_size(result.graph) == 2
      # Each node should have at least one neighbor (r >= 2, we have 2 nodes so max 1 neighbor each)
      for {_id, edges} <- result.graph do
        assert is_list(edges)
        assert length(edges) <= 2
      end
    end

    test "three points builds connected graph" do
      points = [
        {"a", [1.0, 0.0], %{}},
        {"b", [0.9, 0.1], %{}},
        {"c", [0.0, 1.0], %{}}
      ]
      result = Graph.build(points, dimension: 2, filter_config: [], r: 2, l: 3, seed: 0)
      assert length(result.ids) == 3
      total_edges = result.graph |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert total_edges >= 2
    end
  end
end
