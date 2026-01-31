defmodule ElixDb.Store do
  @moduledoc """
  GenServer-backed store for points per collection. Each collection has an ETS table.
  Points are {id, vector, payload}; upsert overwrites by id.

  Search options (opts for `search/5`):
  - `:filter` - map of payload key/value; only points matching all pairs are considered (pre-filter).
  - `:score_threshold` - for cosine or dot_product: only return points with score >= threshold.
  - `:distance_threshold` - for L2: only return points with distance <= threshold.
  - `:with_payload` - include payload in results (default true).
  - `:with_vector` - include vector in results (default false).
  - `:ef` - when using DAZO index: search list size / candidate count for graph traversal (default max(k*3, 50)).
  - `:brute_force` - if true, skip DAZO index and use exact brute-force search (default false).

  By default, search uses the DAZO index when one exists for the collection (built via `DazoIndex.build/4`):
  graph + Hamming on sketches + predicate pruning, then re-rank with full vectors. Pass `brute_force: true`
  to force exact brute-force search. When no index exists, brute-force is used automatically.
  """
  use GenServer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    registry = Keyword.fetch!(opts, :registry)
    data_path = Keyword.get(opts, :data_path, Application.get_env(:elix_db, :data_path, "data.elix_db"))
    dazo_index = Keyword.get(opts, :dazo_index, Application.get_env(:elix_db, :dazo_index, ElixDb.DazoIndex))
    GenServer.start_link(__MODULE__, [registry: registry, data_path: data_path, my_name: name, dazo_index: dazo_index], name: name)
  end

  @impl true
  def init(opts) when is_list(opts) do
    registry = Keyword.fetch!(opts, :registry)
    data_path = Keyword.fetch!(opts, :data_path)
    my_name = Keyword.fetch!(opts, :my_name)
    dazo_index = Keyword.fetch!(opts, :dazo_index)
    state = %{
      registry: registry,
      tables: %{},
      data_path: data_path,
      my_name: my_name,
      dazo_index: dazo_index,
      persist_interval_sec: Application.get_env(:elix_db, :persist_interval_sec),
      persist_after_batch: Application.get_env(:elix_db, :persist_after_batch)
    }
    send(self(), :load_from_disk)
    {:ok, state}
  end

  def persist(server \\ __MODULE__) do
    GenServer.call(server, :persist)
  end

  def upsert(server \\ __MODULE__, collection_name, id, vector, payload \\ %{})
      when is_list(vector) or is_binary(vector) do
    GenServer.call(server, {:upsert, collection_name, id, vector, payload})
  end

  def upsert_batch(server \\ __MODULE__, collection_name, points)
      when is_list(points) do
    GenServer.call(server, {:upsert_batch, collection_name, points})
  end

  def search(server \\ __MODULE__, collection_name, query_vector, k \\ 10, opts \\ []) do
    GenServer.call(server, {:search, collection_name, ensure_list(query_vector), k, opts})
  end

  def get(server \\ __MODULE__, collection_name, id, opts \\ []) do
    GenServer.call(server, {:get, collection_name, id, opts})
  end

  def get_many(server \\ __MODULE__, collection_name, ids, opts \\ []) do
    GenServer.call(server, {:get_many, collection_name, ids, opts})
  end

  def delete(server \\ __MODULE__, collection_name, id) do
    GenServer.call(server, {:delete, collection_name, id})
  end

  def delete_many(server \\ __MODULE__, collection_name, ids) when is_list(ids) do
    GenServer.call(server, {:delete_many, collection_name, ids})
  end

  def delete_by_filter(server \\ __MODULE__, collection_name, filter) when is_map(filter) do
    GenServer.call(server, {:delete_by_filter, collection_name, filter})
  end

  def delete_collection(server \\ __MODULE__, collection_name) do
    GenServer.call(server, {:delete_collection, collection_name})
  end

  @doc """
  Returns all points for a collection as [{id, vector, payload}, ...] for index build.
  """
  def points_for_collection(server \\ __MODULE__, collection_name) do
    GenServer.call(server, {:points_for_collection, collection_name})
  end

  @impl true
  def handle_info(:load_from_disk, state) do
    new_state = case File.read(state.data_path) do
      {:ok, bin} ->
        try do
          payload = :erlang.binary_to_term(bin)
          load_state(state, payload)
        rescue
          _ -> state
        end
      {:error, _} -> state
    end
    if new_state.persist_interval_sec do
      Process.send_after(self(), :persist, new_state.persist_interval_sec * 1000)
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:persist, state) do
    do_persist(state)
    if state.persist_interval_sec do
      Process.send_after(self(), :persist, state.persist_interval_sec * 1000)
    end
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    do_persist(state)
    :ok
  end

  @impl true
  def handle_call({:upsert, collection_name, id, vector, payload}, _from, state) do
    start = System.monotonic_time(:microsecond)
    vec_list = ensure_list(vector)
    result = case validate_upsert(state, collection_name, vec_list) do
      :ok ->
        {table, new_state} = get_or_create_table(state, collection_name)
        :ets.insert(table, {id, vec_list, payload || %{}})
        {:reply, :ok, new_state}
      err -> {:reply, err, state}
    end
    record_timing(:upsert, start)
    result
  end

  @impl true
  def handle_call({:search, collection_name, query_vector, k, opts}, _from, state) do
    start = System.monotonic_time(:microsecond)
    result = case get_collection(state.registry, collection_name) do
      nil -> {:reply, {:error, :collection_not_found}, state}
      coll ->
        # Default: use DAZO index when present. Pass brute_force: true to force exact brute-force.
        idx = ElixDb.DazoIndex.get_index(state.dazo_index, collection_name)
        ef = Keyword.get(opts, :ef, max(k * 3, 50))
        force_brute = Keyword.get(opts, :brute_force, false)
        dazo_result = if not force_brute and idx != nil and (idx[:thresholds] == nil or idx[:thresholds] == []) == false do
          case ElixDb.DazoIndex.get_candidates(state.dazo_index, collection_name, query_vector, ef, opts) do
            {:ok, candidate_ids} when candidate_ids != [] ->
              points = fetch_points_by_ids(state, collection_name, candidate_ids)
              rerank_and_format(points, query_vector, k, opts, coll.distance_metric)
            {:ok, []} -> {:ok, []}
            {:error, _} -> nil
          end
        else
          nil
        end
        if dazo_result != nil do
          record_timing(:search, start)
          {:reply, dazo_result, state}
        else
          do_brute_force_search(collection_name, query_vector, k, opts, state, start)
        end
    end
    result
  end

  def handle_call({:get, collection_name, id, opts}, _from, state) do
    start = System.monotonic_time(:microsecond)
    with_payload = Keyword.get(opts, :with_payload, true)
    with_vector = Keyword.get(opts, :with_vector, false)
    result = case state.tables[collection_name] do
      nil -> {:reply, nil, state}
      table ->
        case :ets.lookup(table, id) do
          [] -> {:reply, nil, state}
          [{^id, vec, payload}] ->
            result = %{id: id}
            result = if with_payload, do: Map.put(result, :payload, payload), else: result
            result = if with_vector, do: Map.put(result, :vector, vec), else: result
            {:reply, result, state}
        end
    end
    record_timing(:get, start)
    result
  end

  @impl true
  def handle_call({:get_many, collection_name, ids, opts}, _from, state) do
    start = System.monotonic_time(:microsecond)
    with_payload = Keyword.get(opts, :with_payload, true)
    with_vector = Keyword.get(opts, :with_vector, false)
    result = case state.tables[collection_name] do
      nil -> {:reply, [], state}
      table ->
        results = Enum.map(ids, fn id ->
          case :ets.lookup(table, id) do
            [] -> nil
            [{^id, vec, payload}] ->
              result = %{id: id}
              result = if with_payload, do: Map.put(result, :payload, payload), else: result
              result = if with_vector, do: Map.put(result, :vector, vec), else: result
              result
          end
        end) |> Enum.reject(&is_nil/1)
        {:reply, results, state}
    end
    record_timing(:get_many, start)
    result
  end

  @impl true
  def handle_call({:delete, collection_name, id}, _from, state) do
    start = System.monotonic_time(:microsecond)
    result = case state.tables[collection_name] do
      nil -> {:reply, :ok, state}
      table ->
        :ets.delete(table, id)
        {:reply, :ok, state}
    end
    record_timing(:delete, start)
    result
  end

  @impl true
  def handle_call({:delete_many, collection_name, ids}, _from, state) do
    start = System.monotonic_time(:microsecond)
    result = case state.tables[collection_name] do
      nil -> {:reply, :ok, state}
      table ->
        for id <- ids, do: :ets.delete(table, id)
        {:reply, :ok, state}
    end
    record_timing(:delete_many, start)
    result
  end

  @impl true
  def handle_call({:delete_by_filter, collection_name, filter}, _from, state) do
    start = System.monotonic_time(:microsecond)
    result = case state.tables[collection_name] do
      nil -> {:reply, :ok, state}
      table ->
        points = :ets.tab2list(table)
        matching = Enum.filter(points, fn {_id, _vec, payload} ->
          Enum.all?(filter, fn {k, v} ->
            Map.get(payload, k) == v or Map.get(payload, to_string(k)) == v
          end)
        end)
        for {id, _, _} <- matching, do: :ets.delete(table, id)
        {:reply, :ok, state}
    end
    record_timing(:delete_by_filter, start)
    result
  end

  @impl true
  def handle_call({:points_for_collection, collection_name}, _from, state) do
    case state.tables[collection_name] do
      nil -> {:reply, {:error, :collection_not_found}, state}
      table ->
        points = :ets.tab2list(table) |> Enum.map(fn {id, vec, payload} -> {id, vec, payload || %{}} end)
        {:reply, {:ok, points}, state}
    end
  end

  @impl true
  def handle_call({:delete_collection, collection_name}, _from, state) do
    new_state = case Map.pop(state.tables, collection_name) do
      {nil, _} -> state
      {table, tables} ->
        :ets.delete(table)
        %{state | tables: tables}
    end
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    start = System.monotonic_time(:microsecond)
    do_persist(state)
    record_timing(:persist, start)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:upsert_batch, collection_name, points}, _from, state) do
    start = System.monotonic_time(:microsecond)
    result = case get_collection(state.registry, collection_name) do
      nil -> {:reply, {:error, :collection_not_found}, state}
      coll ->
        dim = coll.dimension
        parsed = Enum.map(points, fn
          {id, vector, payload} when is_list(vector) or is_binary(vector) ->
            vec_list = ensure_list(vector)
            if length(vec_list) != dim, do: {:error, {:invalid_dimension, id}}, else: {:ok, id, vec_list, payload || %{}}
          {id, _vector, _payload} ->
            {:error, {:invalid_point_format, id}}
          point ->
            {:error, {:invalid_point_format, inspect(point)}}
        end)
        errors = Enum.filter(parsed, &match?({:error, _}, &1))
        if errors != [] do
          {:reply, {:error, errors}, state}
        else
          {table, new_state} = get_or_create_table(state, collection_name)
          for {:ok, id, vec_list, payload} <- parsed do
            :ets.insert(table, {id, vec_list, payload})
          end
          if new_state.persist_after_batch, do: do_persist(new_state)
          {:reply, :ok, new_state}
        end
    end
    record_timing(:upsert_batch, start)
    result
  end

  defp record_timing(operation, start) do
    duration_us = System.monotonic_time(:microsecond) - start
    ElixDb.Metrics.record(ElixDb.Metrics, operation, duration_us)
    :telemetry.execute([:elix_db, :store, operation], %{duration_us: duration_us}, %{})
  end

  defp get_collection(registry, name) do
    case GenServer.call(registry, {:get, name}) do
      nil -> nil
      coll -> coll
    end
  end

  defp validate_upsert(state, collection_name, vector) do
    case get_collection(state.registry, collection_name) do
      nil -> {:error, :collection_not_found}
      coll ->
        if length(vector) != coll.dimension do
          {:error, :invalid_dimension}
        else
          :ok
        end
    end
  end

  defp get_or_create_table(state, collection_name) do
    case state.tables[collection_name] do
      nil ->
        tab = :ets.new(:store_table, [:set, :protected])
        new_state = %{state | tables: Map.put(state.tables, collection_name, tab)}
        {tab, new_state}
      tab -> {tab, state}
    end
  end

  defp payload_matches?(_payload, filter) when map_size(filter) == 0, do: true
  defp payload_matches?(payload, filter) do
    Enum.all?(filter, fn {k, v} ->
      Map.get(payload, k) == v or Map.get(payload, to_string(k)) == v
    end)
  end

  defp apply_score_threshold(sorted, _metric, nil, nil), do: sorted
  defp apply_score_threshold(sorted, :cosine, threshold, _) when is_number(threshold) do
    Enum.filter(sorted, fn {_, score, _, _} -> score >= threshold end)
  end
  defp apply_score_threshold(sorted, :dot_product, threshold, _) when is_number(threshold) do
    Enum.filter(sorted, fn {_, score, _, _} -> score >= threshold end)
  end
  defp apply_score_threshold(sorted, :l2, _, threshold) when is_number(threshold) do
    Enum.filter(sorted, fn {_, distance, _, _} -> distance <= threshold end)
  end
  defp apply_score_threshold(sorted, _metric, _st, _dt), do: sorted

  defp fetch_points_by_ids(state, collection_name, ids) do
    table = state.tables[collection_name]
    if table == nil do
      []
    else
      Enum.flat_map(ids, fn id ->
        case :ets.lookup(table, id) do
          [] -> []
          [{^id, vec, payload}] -> [{id, vec, payload || %{}}]
        end
      end)
    end
  end

  defp rerank_and_format(points, query_vector, k, opts, metric) do
    with_payload = Keyword.get(opts, :with_payload, true)
    with_vector = Keyword.get(opts, :with_vector, false)
    filter = Keyword.get(opts, :filter, %{})
    score_threshold = Keyword.get(opts, :score_threshold)
    distance_threshold = Keyword.get(opts, :distance_threshold)
    # Nx batch re-rank: single batch distance call for all candidates (faster than per-point)
    scored = if points == [] do
      []
    else
      vecs = Enum.map(points, fn {_id, vec, _} -> vec end)
      scores = case metric do
        :cosine -> ElixDb.Similarity.cosine_batch(query_vector, vecs)
        :l2 -> ElixDb.Similarity.l2_batch(query_vector, vecs)
        :dot_product -> ElixDb.Similarity.dot_product_batch(query_vector, vecs)
      end
      points |> Enum.zip(scores) |> Enum.map(fn {{id, vec, payload}, score} -> {id, score, vec, payload} end)
    end
    scored = if map_size(filter) == 0 do
      scored
    else
      Enum.filter(scored, fn {_id, _s, _v, payload} -> payload_matches?(payload, filter) end)
    end
    sorted = case metric do
      :cosine -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :desc)
      :l2 -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :asc)
      :dot_product -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :desc)
    end
    sorted = apply_score_threshold(sorted, metric, score_threshold, distance_threshold)
    results = sorted |> Enum.take(k) |> Enum.map(fn {id, score, vec, payload} ->
      result = %{id: id, score: score}
      result = if with_payload, do: Map.put(result, :payload, payload), else: result
      result = if with_vector, do: Map.put(result, :vector, vec), else: result
      result
    end)
    {:ok, results}
  end

  defp do_brute_force_search(collection_name, query_vector, k, opts, state, start) do
    coll = get_collection(state.registry, collection_name)
    table = state.tables[collection_name]
    if table == nil do
      record_timing(:search, start)
      {:reply, {:ok, []}, state}
    else
      with_payload = Keyword.get(opts, :with_payload, true)
      with_vector = Keyword.get(opts, :with_vector, false)
      filter = Keyword.get(opts, :filter, %{})
      score_threshold = Keyword.get(opts, :score_threshold)
      distance_threshold = Keyword.get(opts, :distance_threshold)
      points = :ets.tab2list(table)
      points = if filter == %{}, do: points, else: Enum.filter(points, fn {_id, _vec, payload} -> payload_matches?(payload, filter) end)
      scored = if points == [] do
        []
      else
        vecs = Enum.map(points, fn {_id, vec, _} -> vec end)
        # Pass list or pre-built Nx tensor; tensor path avoids list-of-lists allocation
        matrix = Nx.tensor(vecs, type: {:f, 32})
        scores = case coll.distance_metric do
          :cosine -> ElixDb.Similarity.cosine_batch(query_vector, matrix)
          :l2 -> ElixDb.Similarity.l2_batch(query_vector, matrix)
          :dot_product -> ElixDb.Similarity.dot_product_batch(query_vector, matrix)
        end
        points |> Enum.zip(scores) |> Enum.map(fn {{id, vec, payload}, score} -> {id, score, vec, payload} end)
      end
      sorted = case coll.distance_metric do
        :cosine -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :desc)
        :l2 -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :asc)
        :dot_product -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :desc)
      end
      sorted = apply_score_threshold(sorted, coll.distance_metric, score_threshold, distance_threshold)
      results = sorted |> Enum.take(k) |> Enum.map(fn {id, score, vec, payload} ->
        result = %{id: id, score: score}
        result = if with_payload, do: Map.put(result, :payload, payload), else: result
        result = if with_vector, do: Map.put(result, :vector, vec), else: result
        result
      end)
      record_timing(:search, start)
      {:reply, {:ok, results}, state}
    end
  end

  defp ensure_list(vec) when is_list(vec), do: vec
  defp ensure_list(vec) when is_binary(vec), do: :erlang.binary_to_list(vec)
  defp ensure_list(vec), do: List.wrap(vec)

  defp do_persist(state) do
    collections = GenServer.call(state.registry, :list)
    points_map = Enum.reduce(state.tables, %{}, fn {coll_name, table}, acc ->
      pts = :ets.tab2list(table) |> Enum.map(fn {id, vec, payload} -> {id, vec, payload} end)
      Map.put(acc, coll_name, pts)
    end)
    payload = %{collections: collections, points: points_map}
    File.write!(state.data_path, :erlang.term_to_binary(payload))
  rescue
    _ -> :ok
  end

  defp load_state(state, %{collections: collections, points: points_map}) do
    for coll <- collections do
      if get_collection(state.registry, coll.name) == nil do
        ElixDb.CollectionRegistry.create_collection(state.registry, coll.name, coll.dimension, coll.distance_metric)
      end
    end
    Enum.reduce(points_map, state, fn {coll_name, points}, acc ->
      if points == [] do
        acc
      else
        {table, new_state} = get_or_create_table(acc, coll_name)
        for {id, vec, payload} <- points do
          :ets.insert(table, {id, vec, payload})
        end
        new_state
      end
    end)
  end
end
