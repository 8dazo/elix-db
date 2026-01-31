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
end
