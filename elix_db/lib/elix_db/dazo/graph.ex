defmodule ElixDb.Dazo.Graph do
  @moduledoc """
  Hub-highway Vamana-style graph build for DAZO. Nodes = point ids; edges store
  {neighbor_id, payload_mask_8bit}. Build uses full-vector distance; search uses Hamming on sketches.

  Options: :dimension, :distance_metric (:cosine | :l2 | :dot_product), :filter_config,
  :r (max degree, default 5, min 2), :alpha (default 1.5), :l (search list size, default 10, >= r),
  :seed (default 0), :build_iters (default 1).
  """
  alias ElixDb.Similarity
  alias ElixDb.Dazo.EAB
  alias ElixDb.Dazo.PredicateMask, as: PM

  @default_r 5
  @default_alpha 1.5
  @default_l 10
  @min_r 2
  @epsilon 1.0e-10

  @doc """
  Builds graph from points [{id, vector, payload}]. Returns
  %{medoid_id, ids, id_to_vector, id_to_sketch, id_to_mask, graph, thresholds}
  where graph[id] = [{neighbor_id, edge_mask}]. thresholds is used for query sketching at search time.
  """
  @spec build(points :: [{term(), [float()], map()}], opts :: keyword()) ::
          %{medoid_id: term(), ids: [term()], id_to_vector: map(), id_to_sketch: map(), id_to_mask: map(), graph: map(), thresholds: [float()]}
          | {:error, term()}
  def build(points, opts) when is_list(points) do
    dim = Keyword.fetch!(opts, :dimension)
    metric = Keyword.get(opts, :distance_metric, :l2)
    filter_config = Keyword.get(opts, :filter_config, [])
    r = max(Keyword.get(opts, :r, @default_r), @min_r)
    alpha = max(Keyword.get(opts, :alpha, @default_alpha), @epsilon)
    l = max(Keyword.get(opts, :l, @default_l), r)
    seed = Keyword.get(opts, :seed, 0)
    iters = max(Keyword.get(opts, :build_iters, 1), 1)

    case points do
      [] -> {:error, :empty_points}
      [single] ->
        {id, vec, payload} = single
        mask = PM.payload_to_mask(payload, filter_config)
        sketch = EAB.sketches([vec], dimension: dim) |> List.first() || 0
        thresholds = EAB.thresholds_for([vec], dimension: dim)
        %{
          medoid_id: id,
          ids: [id],
          id_to_vector: %{id => vec},
          id_to_sketch: %{id => sketch},
          id_to_mask: %{id => mask},
          graph: %{id => []},
          thresholds: thresholds
        }
      _ ->
        ids = Enum.map(points, fn {id, _, _} -> id end)
        vectors = Enum.map(points, fn {_, v, _} -> v end)
        id_to_vector = Map.new(points, fn {id, v, _} -> {id, v} end)
        id_to_sketch = ids |> Enum.zip(EAB.sketches(vectors, dimension: dim)) |> Map.new()
        id_to_mask = Map.new(points, fn {id, _, payload} -> {id, PM.payload_to_mask(payload, filter_config)} end)
        thresholds = EAB.thresholds_for(vectors, dimension: dim)
        medoid_id = medoid(vectors, ids, metric)
        graph = init_random_graph(ids, r, seed)
        graph = run_build_iters(points, id_to_vector, id_to_mask, graph, metric, r, alpha, l, iters, seed)
        %{
          medoid_id: medoid_id,
          ids: ids,
          id_to_vector: id_to_vector,
          id_to_sketch: id_to_sketch,
          id_to_mask: id_to_mask,
          graph: graph,
          thresholds: thresholds
        }
    end
  end

  defp medoid(vectors, ids, metric) do
    centroid = centroid(vectors)
    distances = distance_batch(centroid, vectors, metric)
    idx = Enum.with_index(distances) |> Enum.min_by(fn {d, _} -> d end) |> elem(1)
    Enum.at(ids, idx)
  end

  defp centroid(vectors) do
    n = length(vectors)
    dim = length(hd(vectors))
    Enum.map(0..(dim - 1), fn i -> (Enum.map(vectors, &Enum.at(&1, i)) |> Enum.sum()) / n end)
  end

  defp distance_batch(query, vectors, :l2) do
    Similarity.l2_batch(query, vectors)
  end
  defp distance_batch(query, vectors, :cosine) do
    # lower is better for "distance" (1 - similarity)
    sims = Similarity.cosine_batch(query, vectors)
    Enum.map(sims, fn s -> 1 - s end)
  end
  defp distance_batch(query, vectors, :dot_product) do
    sims = Similarity.dot_product_batch(query, vectors)
    Enum.map(sims, fn s -> -s end)
  end

  defp init_random_graph(ids, r, seed) do
    id_set = MapSet.new(ids)
    Enum.reduce(ids, %{}, fn id, acc ->
      others = MapSet.delete(id_set, id) |> MapSet.to_list()
      n = length(others)
      if n == 0 do
        Map.put(acc, id, [])
      else
        k = min(r, n)
        id_hash = :erlang.phash2(id)
        :rand.seed(:exsss, {seed, seed + id_hash, 0})
        shuffled = Enum.shuffle(others)
        idxs = Enum.take(shuffled, k)
        edges = Enum.map(idxs, fn nbr -> {nbr, 0} end)
        Map.put(acc, id, edges)
      end
    end)
  end

  defp run_build_iters(points, id_to_vector, id_to_mask, graph, metric, r, alpha, l, iters, seed) do
    ids = Enum.map(points, fn {id, _, _} -> id end)
    Enum.reduce(1..iters, graph, fn _, g ->
      :rand.seed(:exsss, {seed, seed + 1, seed + 2})
      order = Enum.shuffle(ids)
      Enum.reduce(order, g, fn id, g2 ->
        vec = id_to_vector[id]
        candidates = greedy_search(id, vec, g2, id_to_vector, metric, l)
        new_edges = robust_prune(id, vec, candidates, g2, id_to_vector, id_to_mask, metric, r, alpha)
        g3 = Map.put(g2, id, new_edges)
        add_reverse_and_prune(g3, id, new_edges, id_to_vector, id_to_mask, metric, r, alpha)
      end)
    end)
  end

  defp greedy_search(start_id, query_vec, graph, id_to_vector, metric, l) do
    visited = MapSet.new()
    candidates = [{distance(query_vec, id_to_vector[start_id], metric), start_id}]
    search_loop(candidates, visited, query_vec, graph, id_to_vector, metric, l)
  end

  defp search_loop(candidates, visited, query_vec, graph, id_to_vector, metric, l) do
    sorted = Enum.sort_by(candidates, fn {d, _} -> d end)
    unvisited = Enum.reject(sorted, fn {_, id} -> MapSet.member?(visited, id) end)
    case unvisited do
      [] -> take_closest_l(visited, query_vec, id_to_vector, metric, l)
      [{_d, id} | rest] ->
        visited = MapSet.put(visited, id)
        neighbors = (graph[id] || []) |> Enum.map(fn {nbr, _} -> nbr end)
        new_cands = Enum.reduce(neighbors, rest, fn nbr, acc ->
          if MapSet.member?(visited, nbr), do: acc, else: [{distance(query_vec, id_to_vector[nbr], metric), nbr} | acc]
        end)
        search_loop(new_cands, visited, query_vec, graph, id_to_vector, metric, l)
    end
  end

  defp take_closest_l(visited, query_vec, id_to_vector, metric, l) do
    visited
    |> MapSet.to_list()
    |> Enum.map(fn id -> {distance(query_vec, id_to_vector[id], metric), id} end)
    |> Enum.sort_by(fn {d, _} -> d end)
    |> Enum.take(l)
    |> Enum.map(fn {_, id} -> id end)
  end

  defp distance(a, b, :l2), do: Similarity.l2_distance(a, b)
  defp distance(a, b, :cosine), do: 1 - Similarity.cosine(a, b)
  defp distance(a, b, :dot_product), do: -Similarity.dot_product(a, b)

  defp robust_prune(node_id, node_vec, candidate_ids, graph, id_to_vector, id_to_mask, metric, r, alpha) do
    current_nbrs = (graph[node_id] || []) |> Enum.map(fn {nbr, _} -> nbr end)
    all_candidates = Enum.uniq(candidate_ids ++ current_nbrs)
    with_dist = Enum.map(all_candidates, fn nbr -> {distance(node_vec, id_to_vector[nbr], metric), nbr} end)
    sorted = Enum.sort_by(with_dist, fn {d, _} -> d end)
    {out, _} = Enum.reduce_while(sorted, {[], nil}, fn {d, nbr}, {acc, min_d} ->
      cond do
        length(acc) >= r and min_d != nil and d < alpha * min_d -> {:halt, {acc, min_d}}
        true ->
          new_acc = acc ++ [{nbr, id_to_mask[nbr] || 0}]
          new_min = if min_d == nil, do: d, else: min(min_d, d)
          {:cont, {new_acc, new_min}}
      end
    end)
    out = Enum.take(out, r)
    if out == [] and sorted != [] do
      [{_d, nearest} | _] = sorted
      [{nearest, id_to_mask[nearest] || 0}]
    else
      out
    end
  end

  defp add_reverse_and_prune(graph, from_id, edges, id_to_vector, id_to_mask, metric, r, alpha) do
    Enum.reduce(edges, graph, fn {nbr_id, _mask}, g ->
      existing = (g[nbr_id] || []) |> Enum.reject(fn {id, _} -> id == from_id end)
      new_list = [{from_id, id_to_mask[from_id] || 0} | existing]
      pruned = if length(new_list) > r do
        nbr_vec = id_to_vector[nbr_id]
        robust_prune(nbr_id, nbr_vec, Enum.map(new_list, &elem(&1, 0)), g, id_to_vector, id_to_mask, metric, r, alpha)
      else
        new_list
      end
      Map.put(g, nbr_id, pruned)
    end)
  end

  @doc """
  Graph search using Hamming distance on sketches and predicate pruning.
  Returns candidate ids (up to ef) for re-ranking with full vectors.
  - medoid_id: entry point
  - query_sketch: 32-bit sketch of query (from EAB.vector_to_sketch)
  - query_mask: 8-bit filter mask (from PredicateMask.filter_to_mask); 0 = no pruning
  - ef: search list size (number of nodes to visit, default 50)
  """
  @spec search_with_sketches(medoid_id :: term(), query_sketch :: non_neg_integer(), graph :: map(),
                             id_to_sketch :: map(), id_to_mask :: map(), query_mask :: 0..255, ef :: pos_integer()) :: [term()]
  def search_with_sketches(medoid_id, query_sketch, graph, id_to_sketch, id_to_mask, query_mask, ef \\ 50) do
    ef = max(ef, 1)
    visited = MapSet.new()
    # candidates: min-heap by Hamming (lower is better); we use a sorted list and take closest
    start_h = Similarity.hamming(query_sketch, id_to_sketch[medoid_id] || 0)
    candidates = [{start_h, medoid_id}]
    search_sketch_loop(candidates, visited, query_sketch, graph, id_to_sketch, id_to_mask, query_mask, ef)
  end

  defp search_sketch_loop(candidates, visited, query_sketch, graph, id_to_sketch, id_to_mask, query_mask, ef) do
    if MapSet.size(visited) >= ef do
      MapSet.to_list(visited)
    else
      sorted = Enum.sort_by(candidates, fn {h, _} -> h end)
      unvisited = Enum.reject(sorted, fn {_, id} -> MapSet.member?(visited, id) end)
      case unvisited do
        [] -> MapSet.to_list(visited)
        [{_h, id} | rest] ->
          visited = MapSet.put(visited, id)
          neighbors = (graph[id] || []) |> Enum.filter(fn {_nbr, edge_mask} -> PM.edge_matches?(edge_mask, query_mask) end)
          new_cands = Enum.reduce(neighbors, rest, fn {nbr, _}, acc ->
            if MapSet.member?(visited, nbr), do: acc, else: [{Similarity.hamming(query_sketch, id_to_sketch[nbr] || 0), nbr} | acc]
          end)
          search_sketch_loop(new_cands, visited, query_sketch, graph, id_to_sketch, id_to_mask, query_mask, ef)
      end
    end
  end
end
