defmodule ElixDb.Dazo.CoarseQuantizer do
  @moduledoc """
  IVF-style coarse quantizer for DAZO: cluster points by EAB sketches, probe only nprobe buckets at query time.
  No full scan: query is sketched, nearest nprobe centroid buckets are found by Hamming, then only those bucket ids are returned for fine search.
  """
  alias ElixDb.Dazo.EAB
  alias ElixDb.Similarity

  @max_iters 5

  @doc """
  Builds coarse quantizer from points [{id, vector, payload}, ...].
  Returns %{centroid_sketches: [non_neg_integer], bucket_id_to_ids: %{0 => [id], ...}, nlist, thresholds, dimension}.
  Options: :dimension, :nlist (default from n), :seed.
  """
  @spec build(points :: [{term(), [float()], map()}], opts :: keyword()) ::
          %{centroid_sketches: [non_neg_integer()], bucket_id_to_ids: %{non_neg_integer() => [term()]}, nlist: non_neg_integer(), thresholds: [float()], dimension: non_neg_integer()}
          | {:error, term()}
  def build(points, opts \\ []) when is_list(points) do
    case points do
      [] -> {:error, :empty_points}
      _ ->
        dim = opts[:dimension] || length(elem(hd(points), 1))
        vectors = Enum.map(points, fn {_, v, _} -> v end)
        ids = Enum.map(points, fn {id, _, _} -> id end)
        n = length(points)
        # Smaller nlist for faster build when n is moderate (e.g. 10k -> 100 instead of 256)
        nlist = opts[:nlist] || min(128, min(4096, max(32, trunc(:math.sqrt(n)))))
        nlist = min(nlist, n)
        nlist = max(nlist, 1)
        seed = Keyword.get(opts, :seed, 0)

        thresholds = EAB.thresholds_for(vectors, dimension: dim)
        sketches = EAB.sketches(vectors, dimension: dim)

        centroid_sketches = kmeans_sketches(sketches, nlist, seed)
        bucket_id_to_ids = assign_to_buckets(ids, sketches, centroid_sketches)

        %{
          centroid_sketches: centroid_sketches,
          bucket_id_to_ids: bucket_id_to_ids,
          nlist: nlist,
          thresholds: thresholds,
          dimension: dim
        }
    end
  end

  @doc """
  Returns nprobe bucket ids (indices) whose centroids are nearest to query_sketch by Hamming distance.
  """
  @spec search(coarse_state :: map(), query_sketch :: non_neg_integer(), nprobe :: pos_integer()) :: [non_neg_integer()]
  def search(coarse_state, query_sketch, nprobe \\ 8) do
    centroids = coarse_state.centroid_sketches
    nprobe = min(nprobe, length(centroids))
    with_dist = Enum.with_index(centroids) |> Enum.map(fn {c, idx} -> {Similarity.hamming(query_sketch, c), idx} end)
    with_dist |> Enum.sort_by(fn {d, _} -> d end) |> Enum.take(nprobe) |> Enum.map(fn {_, idx} -> idx end)
  end

  @doc """
  Collects at most max_ids point ids from the given bucket ids (order preserved; round-robin if capped).
  """
  @spec collect_ids_from_buckets(coarse_state :: map(), bucket_ids :: [non_neg_integer()], max_ids :: pos_integer()) :: [term()]
  def collect_ids_from_buckets(coarse_state, bucket_ids, max_ids) do
    buckets = coarse_state.bucket_id_to_ids
    ids = Enum.flat_map(bucket_ids, fn bid -> Map.get(buckets, bid, []) end)
    Enum.uniq(ids) |> Enum.take(max_ids)
  end

  defp kmeans_sketches(sketches, nlist, seed) do
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    # Initialize: random centroids from sketches (with replacement if nlist > n)
    indices = Enum.map(1..nlist, fn _ -> :rand.uniform(length(sketches)) - 1 end)
    centroids = Enum.map(indices, fn i -> Enum.at(sketches, i) end)
    kmeans_loop(sketches, centroids, 0)
  end

  defp kmeans_loop(sketches, centroids, iter) do
    if iter >= @max_iters do
      centroids
    else
      # Assign each sketch to nearest centroid
      assignments = Enum.map(sketches, fn s ->
        {_d, idx} = centroids |> Enum.with_index() |> Enum.map(fn {c, i} -> {Similarity.hamming(s, c), i} end) |> Enum.min_by(fn {d, _} -> d end)
        idx
      end)
      # New centroids: majority vote per bit in each cluster
      new_centroids = for i <- 0..(length(centroids) - 1) do
        cluster_sketches = Enum.with_index(sketches) |> Enum.filter(fn {_, idx} -> Enum.at(assignments, idx) == i end) |> Enum.map(&elem(&1, 0))
        if cluster_sketches == [] do
          Enum.at(centroids, i)
        else
          majority_vote_sketch(cluster_sketches)
        end
      end
      kmeans_loop(sketches, new_centroids, iter + 1)
    end
  end

  defp majority_vote_sketch(sketches) do
    Enum.reduce(0..31, 0, fn bit, acc ->
      ones = Enum.count(sketches, fn s -> Bitwise.band(Bitwise.bsr(s, bit), 1) == 1 end)
      if ones >= div(length(sketches), 2) + rem(length(sketches), 2), do: acc + Bitwise.bsl(1, bit), else: acc
    end)
  end

  defp assign_to_buckets(ids, sketches, centroid_sketches) do
    pairs = Enum.zip(ids, sketches) |> Enum.map(fn {id, s} ->
      {_d, idx} = centroid_sketches |> Enum.with_index() |> Enum.map(fn {c, i} -> {Similarity.hamming(s, c), i} end) |> Enum.min_by(fn {d, _} -> d end)
      {idx, id}
    end)
    Enum.group_by(pairs, fn {idx, _} -> idx end, fn {_, id} -> id end)
  end
end
