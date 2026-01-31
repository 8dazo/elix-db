defmodule ElixDb.Similarity do
  @moduledoc """
  Vector similarity and distance: cosine similarity, dot product, L2 (Euclidean) distance.
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
    Nx.divide(dot, n) |> Nx.squeeze() |> Nx.to_number()
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
  """
  def cosine_batch(query, vectors) when is_list(query) and is_list(vectors) do
    q = Nx.tensor(query, type: {:f, 32}) |> Nx.new_axis(0)
    m = Nx.tensor(vectors, type: {:f, 32})
    # (1, dim) dot (n, dim)^T -> (1, n); cosine = dot / (norm_q * norm_row)
    dots = Nx.dot(q, Nx.transpose(m)) |> Nx.squeeze()
    norms_q = Nx.LinAlg.norm(q)
    norms_m = Nx.LinAlg.norm(m, axes: [1])
    Nx.divide(dots, Nx.multiply(norms_q, norms_m)) |> Nx.to_flat_list()
  end

  @doc """
  Dot product between one query and many vectors (batch). Returns list of scores.
  """
  def dot_product_batch(query, vectors) when is_list(query) and is_list(vectors) do
    q = Nx.tensor(query, type: {:f, 32}) |> Nx.new_axis(0)
    m = Nx.tensor(vectors, type: {:f, 32})
    Nx.dot(q, Nx.transpose(m)) |> Nx.squeeze() |> Nx.to_flat_list()
  end

  @doc """
  L2 distance between one query and many vectors (batch). Returns list of distances.
  """
  def l2_batch(query, vectors) when is_list(query) and is_list(vectors) do
    q = Nx.tensor(query, type: {:f, 32})
    m = Nx.tensor(vectors, type: {:f, 32})
    # (n, dim) - (1, dim) broadcast -> (n, dim); norm per row -> (n,)
    diff = Nx.subtract(m, q)
    Nx.LinAlg.norm(diff, axes: [1]) |> Nx.to_flat_list()
  end
end
