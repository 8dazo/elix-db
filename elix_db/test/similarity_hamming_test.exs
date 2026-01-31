defmodule ElixDb.SimilarityHammingTest do
  use ExUnit.Case, async: true

  alias ElixDb.Similarity

  describe "hamming/2" do
    test "identical sketches => 0" do
      assert Similarity.hamming(0, 0) == 0
      assert Similarity.hamming(0xFFFFFFFF, 0xFFFFFFFF) == 0
    end

    test "one bit differs => 1" do
      assert Similarity.hamming(0, 1) == 1
      assert Similarity.hamming(3, 2) == 1
    end

    test "all bits differ => 32" do
      assert Similarity.hamming(0, 0xFFFFFFFF) == 32
    end
  end

  describe "hamming_batch/2" do
    test "returns list of distances" do
      assert Similarity.hamming_batch(0, [0, 1, 0xFFFFFFFF]) == [0, 1, 32]
    end
  end
end
