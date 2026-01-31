defmodule ElixDb.Dazo.HnswGraph do
  @moduledoc """
  HNSW-style multi-layer graph (Qdrant/Milvus-like). Full-vector distance for build and search.
  Layer assignment: max_level = floor(-ln(uniform)*mL), mL = 1/ln(M). Entry at top layer;
  search: search_entry (greedy descend beam=1) to layer 0, then search_on_level(ef).
  Options: M, M0, ef_construct, dimension, distance_metric (:cosine | :l2 | :dot_product), seed.
  """
  alias ElixDb.Similarity

  @default_m 16
  @default_ef_construct 100
  @min_m 2

  @doc """
  Builds HNSW index from points [{id, vector, payload}, ...].
  Returns %{ids, id_to_vector, point_levels, links, entry_id, entry_level, dimension, metric, m, m0}.
  Options: :build_workers (default 1; future: parallel layer-0 connection step when > 1).
  """
  @spec build(points :: [{term(), [float()], map()}], opts :: keyword()) ::
          %{ids: [term()], id_to_vector: map(), point_levels: map(), links: map(),
            entry_id: term(), entry_level: non_neg_integer(), dimension: pos_integer(),
            metric: atom(), m: pos_integer(), m0: pos_integer()}
          | {:error, term()}
  def build(points, opts) when is_list(points) do
    case points do
      [] -> {:error, :empty_points}
      [_ | _] ->
        dim = Keyword.fetch!(opts, :dimension)
        metric = Keyword.get(opts, :distance_metric, :cosine)
        m = max(Keyword.get(opts, :m, @default_m), @min_m)
        m0 = Keyword.get(opts, :m0, m * 2)
        ef_construct = max(Keyword.get(opts, :ef_construct, @default_ef_construct), m)
        seed = Keyword.get(opts, :seed, 0)

        ids = Enum.map(points, fn {id, _, _} -> id end)
        id_to_vector = Map.new(points, fn {id, v, _} -> {id, v} end)
        # mL = 1/ln(M) for layer assignment
        inv_ln_m = 1.0 / :math.log(m)

        :rand.seed(:exsss, {seed, seed + 1, seed + 2})
        point_levels = Enum.map(ids, fn id ->
          u = :rand.uniform()
          u = max(u, 1.0e-10)
          level = trunc(-:math.log(u) * inv_ln_m)
          {id, max(0, level)}
        end) |> Map.new()

        # Build by inserting one by one
        {links, entry_id, entry_level} = Enum.reduce(Enum.with_index(ids), {%{}, nil, -1}, fn {id, idx}, {links_acc, ep, ep_level} ->
          vec = id_to_vector[id]
          l = point_levels[id]
          # Current graph state: only nodes 0..idx-1 exist
          current_links = Map.take(links_acc, Enum.take(ids, idx))
          current_levels = Map.take(point_levels, Enum.take(ids, idx))

          {new_links, new_ep, new_ep_level} = if ep == nil do
            # First node: no edges, it's the entry
            links_at_id = for lev <- 0..l, into: %{}, do: {lev, []}
            {Map.put(links_acc, id, links_at_id), id, l}
          else
            # Find entry at top: start from ep, descend to level l+1 (greedy beam=1)
            ep_at_l_plus = search_entry(ep, ep_level, l + 1, vec, current_links, current_levels, id_to_vector, metric)
            # From level l down to 0: search_layer for ef_construct candidates, connect M
            levels_down = if l >= 0, do: l..0//-1, else: []
            {links_after, _} = Enum.reduce(levels_down, {links_acc, ep_at_l_plus}, fn level, {links_in, entry_at_level} ->
              cand_ids = search_on_level(entry_at_level, level, vec, ef_construct, links_in, current_levels, id_to_vector, metric)
              max_conn = if level == 0, do: m0, else: m
              selected = select_neighbors(cand_ids, vec, id_to_vector, metric, max_conn)
              links_out = add_bidirectional(links_in, id, selected, level, l)
              links_out = prune_neighbors(links_out, id, selected, level, max_conn, id_to_vector, metric)
              next_entry = if selected == [], do: entry_at_level, else: hd(selected)
              {links_out, next_entry}
            end)
            # Update entry if new node has higher level
            new_ep = if l > ep_level, do: id, else: ep
            new_ep_level = if l > ep_level, do: l, else: ep_level
            {links_after, new_ep, new_ep_level}
          end
          {new_links, new_ep, new_ep_level}
        end)

        %{
          ids: ids,
          id_to_vector: id_to_vector,
          point_levels: point_levels,
          links: links,
          entry_id: entry_id,
          entry_level: entry_level,
          dimension: dim,
          metric: metric,
          m: m,
          m0: m0
        }
    end
  end

  # Greedy search for single nearest at each level (beam=1) from entry_id at entry_level down to target_level.
  # Returns the node id at target_level that is nearest to query_vec.
  defp search_entry(entry_id, entry_level, target_level, _query_vec, _links, _point_levels, _id_to_vector, _metric) when target_level >= entry_level do
    entry_id
  end

  defp search_entry(entry_id, entry_level, target_level, query_vec, links, _point_levels, id_to_vector, metric) do
    # Descend from entry_level down to target_level: at each level move to nearest neighbor to query
    levels_to_walk = (target_level..(entry_level - 1)) |> Enum.to_list() |> Enum.reverse()
    Enum.reduce(levels_to_walk, entry_id, fn level, current_id ->
      neighbors = (links[current_id] || %{})[level] || []
      if neighbors == [] do
        current_id
      else
        vecs = Enum.map(neighbors, fn nbr -> id_to_vector[nbr] end)
        dists = distance_batch(query_vec, vecs, metric)
        idx = dists |> Enum.with_index() |> Enum.min_by(fn {d, _} -> d end) |> elem(1)
        Enum.at(neighbors, idx)
      end
    end)
  end

  # Beam search on a single level: start from entry_id, expand up to ef nearest by distance.
  defp search_on_level(entry_id, level, query_vec, ef, links, point_levels, id_to_vector, metric) do
    nodes_at_level = point_levels |> Enum.filter(fn {_id, l} -> l >= level end) |> Enum.map(fn {id, _} -> id end)
    if nodes_at_level == [] or not (entry_id in nodes_at_level) do
      []
    else
      entry_dist = distance(query_vec, id_to_vector[entry_id], metric)
      # candidates: min-heap by distance (we use sorted list, pop closest)
      candidates = [{entry_dist, entry_id}]
      visited = MapSet.new()
      search_level_loop(candidates, visited, query_vec, level, ef, links, point_levels, id_to_vector, metric)
    end
  end

  # Return ef nearest ids. Maintain nearest list (max ef, sorted by dist asc); expand until no improvement.
  defp search_level_loop(candidates, visited, query_vec, level, ef, links, point_levels, id_to_vector, metric) do
    sorted_cand = Enum.sort_by(candidates, fn {d, _} -> d end)
    unvisited = Enum.reject(sorted_cand, fn {_, id} -> MapSet.member?(visited, id) end)
    case unvisited do
      [] ->
        # Return all visited, sorted by distance (nearest first), take ef
        visited |> MapSet.to_list()
          |> Enum.map(fn id -> {distance(query_vec, id_to_vector[id], metric), id} end)
          |> Enum.sort_by(fn {d, _} -> d end)
          |> Enum.take(ef)
          |> Enum.map(fn {_, id} -> id end)
      [{_d, id} | rest] ->
        visited = MapSet.put(visited, id)
        neighbors = (links[id] || %{})[level] || []
        new_cands = Enum.reduce(neighbors, rest, fn nbr, acc ->
          if MapSet.member?(visited, nbr), do: acc, else: [{distance(query_vec, id_to_vector[nbr], metric), nbr} | acc]
        end)
        # Stop when we have ef and closest candidate is worse than worst in visited
        nearest_dists = MapSet.to_list(visited) |> Enum.map(fn i -> {distance(query_vec, id_to_vector[i], metric), i} end) |> Enum.sort_by(fn {d0, _} -> d0 end)
        worst_in_nearest = if length(nearest_dists) >= ef, do: (nearest_dists |> Enum.at(ef - 1) |> elem(0)), else: nil
        if worst_in_nearest != nil and (new_cands == [] or (hd(Enum.sort_by(new_cands, fn {d0, _} -> d0 end)) |> elem(0)) >= worst_in_nearest) do
          nearest_dists |> Enum.take(ef) |> Enum.map(fn {_, i} -> i end)
        else
          search_level_loop(new_cands, visited, query_vec, level, ef, links, point_levels, id_to_vector, metric)
        end
    end
  end

  defp distance(a, b, :l2), do: Similarity.l2_distance(a, b)
  defp distance(a, b, :cosine), do: 1 - Similarity.cosine(a, b)
  defp distance(a, b, :dot_product), do: -Similarity.dot_product(a, b)

  defp distance_batch(query, vectors, :l2), do: Similarity.l2_batch(query, vectors)
  defp distance_batch(query, vectors, :cosine) do
    Similarity.cosine_batch(query, vectors) |> Enum.map(fn s -> 1 - s end)
  end
  defp distance_batch(query, vectors, :dot_product) do
    Similarity.dot_product_batch(query, vectors) |> Enum.map(fn s -> -s end)
  end

  defp select_neighbors(candidate_ids, query_vec, id_to_vector, metric, m) do
    if candidate_ids == [] do
      []
    else
      vecs = Enum.map(candidate_ids, fn i -> id_to_vector[i] end)
      dists = distance_batch(query_vec, vecs, metric)
      candidate_ids
      |> Enum.zip(dists)
      |> Enum.sort_by(fn {_, d} -> d end)
      |> Enum.take(m)
      |> Enum.map(fn {id, _} -> id end)
    end
  end

  defp add_bidirectional(links, new_id, selected, level, new_level) do
    new_links = links[new_id] || for(lev <- 0..new_level, into: %{}, do: {lev, []})
    new_links = Map.put(new_links, level, selected)
    links = Map.put(links, new_id, new_links)
    Enum.reduce(selected, links, fn nbr, acc ->
      nbr_levels = acc[nbr] || %{}
      nbr_at_level = (nbr_levels[level] || []) ++ [new_id]
      nbr_levels = Map.put(nbr_levels, level, nbr_at_level)
      Map.put(acc, nbr, nbr_levels)
    end)
  end

  defp prune_neighbors(links, _new_id, selected, level, max_conn, id_to_vector, metric) do
    Enum.reduce(selected, links, fn nbr, acc ->
      nbr_links = (acc[nbr] || %{})[level] || []
      if length(nbr_links) <= max_conn do
        acc
      else
        nbr_vec = id_to_vector[nbr]
        vecs = Enum.map(nbr_links, fn i -> id_to_vector[i] end)
        dists = distance_batch(nbr_vec, vecs, metric)
        pruned = nbr_links
          |> Enum.zip(dists)
          |> Enum.sort_by(fn {_, d} -> d end)
          |> Enum.take(max_conn)
          |> Enum.map(fn {id, _} -> id end)
        nbr_levels = Map.put(acc[nbr] || %{}, level, pruned)
        Map.put(acc, nbr, nbr_levels)
      end
    end)
  end

  @doc """
  Search: returns up to ef candidate ids (for re-ranking). entry_id/entry_level from index;
  query_vec; ef search list size.
  """
  @spec search(index :: map(), query_vec :: [float()], ef :: pos_integer()) :: [term()]
  def search(index, query_vec, ef) do
    entry_id = index.entry_id
    entry_level = index.entry_level
    links = index.links
    point_levels = index.point_levels
    id_to_vector = index.id_to_vector
    metric = index.metric

    if entry_id == nil do
      []
    else
      # Descend from entry to level 0 (greedy beam=1)
      entry_at_0 = search_entry(entry_id, entry_level, 0, query_vec, links, point_levels, id_to_vector, metric)
      ef = max(ef, 1)
      # Search on level 0 with ef
      search_on_level(entry_at_0, 0, query_vec, ef, links, point_levels, id_to_vector, metric)
    end
  end
end
