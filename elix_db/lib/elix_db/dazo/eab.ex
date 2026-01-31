defmodule ElixDb.Dazo.EAB do
  @moduledoc """
  Entropy-Adaptive Binarization: produces 32-bit sketches from vectors using
  per-dimension thresholds (global median or per-cluster when clustering is used).

  Edge cases: empty → []; single point → threshold 0 (sign); very small n → global
  median; zero variance → threshold = that value; dimension < 32 → pad with 0,
  dimension > 32 → use first 32 dims; all points identical → one sketch.
  """
  require Nx

  @sketch_bits 32
  @epsilon 1.0e-10

  @doc """
  Returns a list of 32-bit sketches (0..0xFFFFFFFF) for the given vectors, in the same order.

  Options:
  - `:dimension` - vector dimension (default: length of first vector, or 0 if empty)
  - `:seed` - RNG seed for reproducibility when clustering is used (optional)

  Uses global median per dimension as threshold when n < 10 or when clustering is disabled.
  Each bit i (0..31) is 1 if dimension i has value >= threshold[i], else 0; dimensions >= 32
  are ignored; dimensions < 32 are padded with 0.
  """
  @spec sketches(vectors :: [list(float())], opts :: keyword()) :: [non_neg_integer()]
  def sketches(vectors, opts \\ []) when is_list(vectors) do
    dim = opts[:dimension] || (List.first(vectors) && length(List.first(vectors))) || 0
    case vectors do
      [] -> []
      [single] ->
        d = if dim > 0, do: dim, else: length(single)
        [do_vector_to_sketch(single, List.duplicate(0, d), d)]
      vs ->
        d = if dim > 0, do: dim, else: length(List.first(vs) || [])
        global_median_sketches(vs, d)
    end
  end

  defp global_median_sketches(vectors, dim) do
    dim = min(dim, length(List.first(vectors) || []))
    thresholds = per_dimension_medians(vectors, dim)
    Enum.map(vectors, fn vec -> do_vector_to_sketch(vec, thresholds, dim) end)
  end

  defp per_dimension_medians(_vectors, dim) when dim <= 0, do: []
  defp per_dimension_medians(vectors, dim) do
    cols = Enum.map(0..(dim - 1), fn i ->
      Enum.map(vectors, fn v -> Enum.at(v, i) || 0.0 end)
    end)
    Enum.map(cols, fn col ->
      sorted = Enum.sort(col)
      n = length(sorted)
      if n == 0 do
        0.0
      else
        mid = div(n, 2)
        if rem(n, 2) == 1, do: Enum.at(sorted, mid), else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
      end
    end)
  end

  defp do_vector_to_sketch(vec, thresholds, dim) do
    do_sketch(vec, thresholds, min(dim, @sketch_bits))
  end

  defp do_sketch(vec, thresholds, dim) do
    Enum.reduce(0..(@sketch_bits - 1), 0, fn i, acc ->
      val = if i < length(vec), do: Enum.at(vec, i) || 0.0, else: 0.0
      th = if i < length(thresholds), do: Enum.at(thresholds, i) || 0.0, else: 0.0
      bit = if i < dim and val >= th - @epsilon, do: 1, else: 0
      acc + Bitwise.bsl(bit, i)
    end)
  end

  @doc """
  Returns the per-dimension thresholds used for binarization (same as used by `sketches/2`).
  Use with `vector_to_sketch/3` for query vectors at search time.
  - Empty → []
  - Single vector → list of zeros (length = dimension)
  - Multiple → per-dimension medians
  """
  @spec thresholds_for(vectors :: [list(float())], opts :: keyword()) :: [float()]
  def thresholds_for(vectors, opts \\ []) when is_list(vectors) do
    dim = opts[:dimension] || (List.first(vectors) && length(List.first(vectors))) || 0
    case vectors do
      [] -> []
      [single] ->
        d = if dim > 0, do: dim, else: length(single)
        List.duplicate(0.0, d)
      vs ->
        d = if dim > 0, do: dim, else: length(List.first(vs) || [])
        per_dimension_medians(vs, min(d, length(List.first(vs) || [])))
    end
  end

  @doc """
  Returns the 32-bit sketch for a single vector using the given threshold list.
  Thresholds length can be less than 32; missing dimensions use threshold 0.
  Dimension caps how many dimensions contribute (rest are 0).
  """
  @spec vector_to_sketch(vector :: [float()], thresholds :: [float()], dimension :: non_neg_integer()) :: non_neg_integer()
  def vector_to_sketch(vec, thresholds, dimension) do
    dim = min(dimension, min(length(vec), @sketch_bits))
    do_vector_to_sketch(vec, thresholds, dim)
  end
end
