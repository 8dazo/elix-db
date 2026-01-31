defmodule ElixDb.Store do
  @moduledoc """
  GenServer-backed store for points per collection. Each collection has an ETS table.
  Points are {id, vector, payload}; upsert overwrites by id.
  """
  use GenServer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    registry = Keyword.fetch!(opts, :registry)
    data_path = Keyword.get(opts, :data_path, Application.get_env(:elix_db, :data_path, "data.elix_db"))
    GenServer.start_link(__MODULE__, [registry: registry, data_path: data_path], name: name)
  end

  @impl true
  def init(opts) when is_list(opts) do
    registry = Keyword.fetch!(opts, :registry)
    data_path = Keyword.fetch!(opts, :data_path)
    state = %{registry: registry, tables: %{}, data_path: data_path}
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
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    do_persist(state)
    :ok
  end

  @impl true
  def handle_call({:upsert, collection_name, id, vector, payload}, _from, state) do
    vec_list = ensure_list(vector)
    case validate_upsert(state, collection_name, vec_list) do
      :ok ->
        {table, new_state} = get_or_create_table(state, collection_name)
        :ets.insert(table, {id, vec_list, payload || %{}})
        {:reply, :ok, new_state}
      err -> {:reply, err, state}
    end
  end

  @impl true
  def handle_call({:search, collection_name, query_vector, k, opts}, _from, state) do
    case get_collection(state.registry, collection_name) do
      nil -> {:reply, {:error, :collection_not_found}, state}
      coll ->
        table = state.tables[collection_name]
        if table == nil do
          {:reply, {:ok, []}, state}
        else
          with_payload = Keyword.get(opts, :with_payload, true)
          with_vector = Keyword.get(opts, :with_vector, false)
          points = :ets.tab2list(table)
          scored = Enum.map(points, fn {id, vec, payload} ->
            score = case coll.distance_metric do
              :cosine -> ElixDb.Similarity.cosine(query_vector, vec)
              :l2 -> ElixDb.Similarity.l2_distance(query_vector, vec)
            end
            {id, score, vec, payload}
          end)
          sorted = case coll.distance_metric do
            :cosine -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :desc)
            :l2 -> Enum.sort_by(scored, fn {_, s, _, _} -> s end, :asc)
          end
          results = sorted |> Enum.take(k) |> Enum.map(fn {id, score, vec, payload} ->
            result = %{id: id, score: score}
            result = if with_payload, do: Map.put(result, :payload, payload), else: result
            result = if with_vector, do: Map.put(result, :vector, vec), else: result
            result
          end)
          {:reply, {:ok, results}, state}
        end
    end
  end

  @impl true
  def handle_call({:get, collection_name, id, opts}, _from, state) do
    with_payload = Keyword.get(opts, :with_payload, true)
    with_vector = Keyword.get(opts, :with_vector, false)
    case state.tables[collection_name] do
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
  end

  @impl true
  def handle_call({:get_many, collection_name, ids, opts}, _from, state) do
    with_payload = Keyword.get(opts, :with_payload, true)
    with_vector = Keyword.get(opts, :with_vector, false)
    case state.tables[collection_name] do
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
  end

  @impl true
  def handle_call({:delete, collection_name, id}, _from, state) do
    case state.tables[collection_name] do
      nil -> {:reply, :ok, state}
      table ->
        :ets.delete(table, id)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:delete_many, collection_name, ids}, _from, state) do
    case state.tables[collection_name] do
      nil -> {:reply, :ok, state}
      table ->
        for id <- ids, do: :ets.delete(table, id)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:delete_by_filter, collection_name, filter}, _from, state) do
    case state.tables[collection_name] do
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
  end

  @impl true
  def handle_call(:persist, _from, state) do
    do_persist(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:upsert_batch, collection_name, points}, _from, state) do
    case get_collection(state.registry, collection_name) do
      nil -> {:reply, {:error, :collection_not_found}, state}
      coll ->
        dim = coll.dimension
        parsed = Enum.map(points, fn {id, vector, payload} ->
          vec_list = ensure_list(vector)
          if length(vec_list) != dim, do: {:error, {:invalid_dimension, id}}, else: {:ok, id, vec_list, payload || %{}}
        end)
        errors = Enum.filter(parsed, &match?({:error, _}, &1))
        if errors != [] do
          {:reply, {:error, errors}, state}
        else
          {table, new_state} = get_or_create_table(state, collection_name)
          for {:ok, id, vec_list, payload} <- parsed do
            :ets.insert(table, {id, vec_list, payload})
          end
          {:reply, :ok, new_state}
        end
    end
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
