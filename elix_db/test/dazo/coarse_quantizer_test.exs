defmodule ElixDb.Dazo.CoarseQuantizerTest do
  use ExUnit.Case, async: true

  alias ElixDb.Dazo.CoarseQuantizer
  alias ElixDb.Dazo.EAB

  describe "build/2" do
    test "returns error for empty points" do
      assert {:error, :empty_points} = CoarseQuantizer.build([], [])
    end

    test "builds coarse state with centroid_sketches and bucket_id_to_ids" do
      points = for i <- 1..100, do: {"p#{i}", (for _ <- 1..64, do: :rand.uniform()), %{}}
      coarse = CoarseQuantizer.build(points, dimension: 64, nlist: 10)
      assert coarse.nlist == 10
      assert length(coarse.centroid_sketches) == 10
      assert is_map(coarse.bucket_id_to_ids)
      assert length(coarse.thresholds) == 64
      total = coarse.bucket_id_to_ids |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert total == 100
    end

    test "search returns nprobe bucket ids by Hamming" do
      points = for i <- 1..50, do: {"p#{i}", (for _ <- 1..32, do: :rand.uniform()), %{}}
      coarse = CoarseQuantizer.build(points, dimension: 32, nlist: 5)
      query_vec = for _ <- 1..32, do: :rand.uniform()
      query_sketch = EAB.vector_to_sketch(query_vec, coarse.thresholds, 32)
      bucket_ids = CoarseQuantizer.search(coarse, query_sketch, 3)
      assert length(bucket_ids) == 3
      assert Enum.all?(bucket_ids, &(&1 >= 0 and &1 < coarse.nlist))
    end

    test "collect_ids_from_buckets returns at most max_ids" do
      points = for i <- 1..20, do: {"p#{i}", (for _ <- 1..32, do: :rand.uniform()), %{}}
      coarse = CoarseQuantizer.build(points, dimension: 32, nlist: 4)
      bucket_ids = [0, 1]
      ids = CoarseQuantizer.collect_ids_from_buckets(coarse, bucket_ids, 5)
      assert length(ids) <= 5
      assert Enum.all?(ids, &String.starts_with?(&1, "p"))
    end
  end
end
