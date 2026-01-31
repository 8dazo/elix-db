defmodule ElixDb.Similarity do
  @moduledoc """
  Vector similarity and distance: cosine similarity, dot product, L2 (Euclidean) distance,
  and Hamming distance for 32-bit binary sketches (DAZO).
  """
  require Nx

  @doc """
  Cosine similarity between two vectors (lists). Returns value in [-1, 1].
  Higher = more similar.
  """
  def cosine(a, b) when is_list(a) and is_list(b) do
    a = Nx.tensor(a, type: {:f, 32})
    b = Nx.tensor(b, type: {:f, 32})
    dot = Nx.dot(a, b)
    norm_a = Nx.LinAlg.norm(a)
    norm_b = Nx.LinAlg.norm(b)
    n = Nx.multiply(norm_a, norm_b)
    # Avoid division by zero for zero-norm vectors; treat as orthogonal (0)
    result = Nx.select(Nx.greater(n, 0), Nx.divide(dot, n), Nx.tensor(0.0, type: {:f, 32}))
    result |> Nx.squeeze() |> Nx.to_number()
  end

  @doc """
  Dot product between two vectors (lists). Higher = more similar when vectors are normalized.
  Equivalent to cosine similarity for unit-length vectors.
  """
  def dot_product(a, b) when is_list(a) and is_list(b) do
    a = Nx.tensor(a, type: {:f, 32})
    b = Nx.tensor(b, type: {:f, 32})
    Nx.dot(a, b) |> Nx.squeeze() |> Nx.to_number()
  end

  @doc """
  L2 (Euclidean) distance between two vectors. Lower = closer.
  """
  def l2_distance(a, b) when is_list(a) and is_list(b) do
    a = Nx.tensor(a, type: {:f, 32})
    b = Nx.tensor(b, type: {:f, 32})
    Nx.subtract(a, b) |> Nx.LinAlg.norm() |> Nx.squeeze() |> Nx.to_number()
  end

  # Batch APIs: query is 1D list, vectors is list of lists (n vectors). Returns list of scores/distances.

  @doc """
  Cosine similarity between one query vector and many vectors (batch). Returns list of scores.
  Accepts vectors as list of lists or an Nx tensor of shape {n, dim} (faster for large n).
  """
  def cosine_batch(query, vectors) when is_list(query) and is_list(vectors) do
    m = Nx.tensor(vectors, type: {:f, 32})
    cosine_batch_tensor(query, m)
  end

  def cosine_batch(query, %Nx.Tensor{} = m) when is_list(query) do
    cosine_batch_tensor(query, m)
  end

  defp cosine_batch_tensor(query, m) do
    q = Nx.tensor(query, type: {:f, 32}) |> Nx.new_axis(0)
    dots = Nx.dot(q, Nx.transpose(m)) |> Nx.squeeze()
    norms_q = Nx.LinAlg.norm(q)
    norms_m = Nx.LinAlg.norm(m, axes: [1])
    denom = Nx.multiply(norms_q, norms_m)
    result = Nx.select(Nx.greater(denom, 0), Nx.divide(dots, denom), Nx.broadcast(0.0, Nx.shape(dots)))
    result |> Nx.to_flat_list()
  end

  @doc """
  Dot product between one query and many vectors (batch). Returns list of scores.
  Accepts vectors as list of lists or an Nx tensor of shape {n, dim}.
  """
  def dot_product_batch(query, vectors) when is_list(query) and is_list(vectors) do
    m = Nx.tensor(vectors, type: {:f, 32})
    dot_product_batch_tensor(query, m)
  end

  def dot_product_batch(query, %Nx.Tensor{} = m) when is_list(query) do
    dot_product_batch_tensor(query, m)
  end

  defp dot_product_batch_tensor(query, m) do
    q = Nx.tensor(query, type: {:f, 32}) |> Nx.new_axis(0)
    Nx.dot(q, Nx.transpose(m)) |> Nx.squeeze() |> Nx.to_flat_list()
  end

  @doc """
  L2 distance between one query and many vectors (batch). Returns list of distances.
  Accepts vectors as list of lists or an Nx tensor of shape {n, dim}.
  """
  def l2_batch(query, vectors) when is_list(query) and is_list(vectors) do
    m = Nx.tensor(vectors, type: {:f, 32})
    l2_batch_tensor(query, m)
  end

  def l2_batch(query, %Nx.Tensor{} = m) when is_list(query) do
    l2_batch_tensor(query, m)
  end

  defp l2_batch_tensor(query, m) do
    q = Nx.tensor(query, type: {:f, 32})
    diff = Nx.subtract(m, q)
    Nx.LinAlg.norm(diff, axes: [1]) |> Nx.to_flat_list()
  end

  # --- Hamming distance for 32-bit sketches (DAZO) ---

  @doc """
  Hamming distance between two 32-bit sketches (number of differing bits).
  Lower = more similar. Used for graph traversal in DAZO.
  """
  @spec hamming(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def hamming(a, b) when is_integer(a) and is_integer(b) do
    popcount(Bitwise.bxor(a, b))
  end

  @doc """
  Hamming distance between one query sketch and many sketches (batch).
  Returns list of distances (0..32).
  """
  @spec hamming_batch(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  def hamming_batch(query_sketch, sketches) when is_list(sketches) do
    Enum.map(sketches, &hamming(query_sketch, &1))
  end

  defp popcount(x) when is_integer(x) and x >= 0 do
    # 32-bit popcount (parallel bit count)
    x = Bitwise.band(x, 0x55555555) + Bitwise.band(Bitwise.bsr(x, 1), 0x55555555)
    x = Bitwise.band(x, 0x33333333) + Bitwise.band(Bitwise.bsr(x, 2), 0x33333333)
    x = Bitwise.band(x, 0x0F0F0F0F) + Bitwise.band(Bitwise.bsr(x, 4), 0x0F0F0F0F)
    x = Bitwise.band(x, 0x00FF00FF) + Bitwise.band(Bitwise.bsr(x, 8), 0x00FF00FF)
    Bitwise.band(x, 0x0000FFFF) + Bitwise.band(Bitwise.bsr(x, 16), 0x0000FFFF)
  end
end
