defmodule ElixDb.Dazo.EABTest do
  use ExUnit.Case, async: true

  alias ElixDb.Dazo.EAB

  describe "sketches/2" do
    test "empty vectors returns empty list" do
      assert EAB.sketches([]) == []
      assert EAB.sketches([], dimension: 4) == []
    end

    test "single point uses threshold 0 (sign-like)" do
      sk = EAB.sketches([[1.0, -0.5, 0.0, 0.5]])
      assert length(sk) == 1
      # first dim 1 >= 0 => 1, second -0.5 < 0 => 0, third 0 >= -epsilon => 1, fourth 0.5 >= 0 => 1
      assert [s] = sk
      assert Bitwise.band(s, 1) == 1
      assert Bitwise.band(Bitwise.bsr(s, 1), 1) == 0
      assert Bitwise.band(Bitwise.bsr(s, 2), 1) == 1
      assert Bitwise.band(Bitwise.bsr(s, 3), 1) == 1
    end

    test "two points: median threshold per dimension" do
      # dim0: [1, 3] median=2, dim1: [0, 4] median=2
      vecs = [[1.0, 0.0], [3.0, 4.0]]
      sk = EAB.sketches(vecs, dimension: 2)
      assert length(sk) == 2
      # vec0: 1 < 2 => 0, 0 < 2 => 0 => sketch 0
      # vec1: 3 >= 2 => 1, 4 >= 2 => 1 => sketch 3 (bits 0 and 1)
      assert Enum.at(sk, 0) == 0
      assert Enum.at(sk, 1) == 3
    end

    test "same order as input" do
      vecs = [[1.0], [2.0], [3.0]]
      sk = EAB.sketches(vecs, dimension: 1)
      assert length(sk) == 3
      # median of [1,2,3] = 2. So vec0: 1<2=>0, vec1: 2>=2=>1, vec2: 3>=2=>1
      assert Enum.at(sk, 0) == 0
      assert Enum.at(sk, 1) == 1
      assert Enum.at(sk, 2) == 1
    end

    test "zero variance: all same value => same sketch" do
      vecs = [[5.0, 5.0], [5.0, 5.0]]
      sk = EAB.sketches(vecs, dimension: 2)
      assert length(sk) == 2
      [a, b] = sk
      assert a == b
      # threshold = 5, val >= 5 => 1
      assert a == 3
    end

    test "dimension < 32: pads with 0" do
      vecs = [[1.0]]
      sk = EAB.sketches(vecs, dimension: 4)
      assert length(sk) == 1
      s = hd(sk)
      assert Bitwise.band(s, 1) == 1
      assert Bitwise.band(Bitwise.bsr(s, 4), 1) == 0
    end

    test "dimension > 32: uses first 32 dims" do
      vec = List.duplicate(1.0, 40)
      sk = EAB.sketches([vec], dimension: 40)
      assert length(sk) == 1
      # first 32 dims all 1 => 0xFFFFFFFF
      assert hd(sk) == 0xFFFFFFFF
    end
  end

  describe "vector_to_sketch/3" do
    test "public API matches internal behavior" do
      thresholds = [0.5, 0.5]
      assert EAB.vector_to_sketch([1.0, 0.0], thresholds, 2) == 1
      assert EAB.vector_to_sketch([0.0, 1.0], thresholds, 2) == 2
    end
  end
end
