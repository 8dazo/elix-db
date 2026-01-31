defmodule ElixDb.DazoIndex do
  @moduledoc """
  GenServer that holds per-collection DAZO index (sketches, graph, masks, thresholds).
  Build from Store; persist/load index. Search uses graph + Hamming on sketches + predicate pruning, then re-ranks with full vectors from Store.
  """
  use GenServer

  alias ElixDb.Dazo.EAB
  alias ElixDb.Dazo.PredicateMask, as: PM
  alias ElixDb.Dazo.Graph
  alias ElixDb.Dazo.CoarseQuantizer
  alias ElixDb.Dazo.HnswGraph

  @index_version 1
  # Below this many vectors, do not build index; search uses brute-force (like Qdrant full_scan_threshold).
  @full_scan_threshold 500
  # Use IVF-style coarse quantizer when n > coarse_threshold; between full_scan_threshold and coarse_threshold use HNSW.
  @coarse_threshold 5_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    data_path = Keyword.get(opts, :data_path, Application.get_env(:elix_db, :dazo_index_path, "dazo_index.elix_db"))
    GenServer.start_link(__MODULE__, [data_path: data_path], name: name)
  end

  def build(server \\ __MODULE__, store, collection_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(server, {:build, store, collection_name, opts}, timeout)
  end

  def get_index(server \\ __MODULE__, collection_name) do
    GenServer.call(server, {:get_index, collection_name})
  end

  @doc """
  Returns candidate ids from graph search (Hamming + predicate pruning). No Store access.
  Caller (Store) fetches vectors and re-ranks. Options: :filter, :ef.
  """
  def get_candidates(server \\ __MODULE__, collection_name, query_vector, ef \\ 50, opts \\ []) do
    GenServer.call(server, {:get_candidates, collection_name, ensure_list(query_vector), ef, opts})
  end

  def persist(server \\ __MODULE__, path \\ nil) do
    GenServer.call(server, {:persist, path})
  end

  def load(server \\ __MODULE__, path \\ nil) do
    GenServer.call(server, {:load, path})
  end

  @impl true
  def init(opts) do
    data_path = Keyword.fetch!(opts, :data_path)
    state = %{indexes: %{}, data_path: data_path}
    send(self(), :load_from_disk)
    {:ok, state}
  end

  @impl true
  def handle_info(:load_from_disk, state) do
    path = state.data_path
    new_state = case File.read(path) do
      {:ok, bin} ->
        try do
          payload = :erlang.binary_to_term(bin)
          load_payload(state, payload)
        rescue
          _ -> state
        end
      {:error, _} -> state
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:build, store, collection_name, opts}, _from, state) do
    case ElixDb.Store.points_for_collection(store, collection_name) do
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:ok, points} when points == [] -> {:reply, {:error, :empty_collection}, state}
      {:ok, points} ->
        registry = Keyword.get(opts, :registry, ElixDb.CollectionRegistry)
        coll = get_collection(registry, collection_name)
        if coll == nil do
          {:reply, {:error, :collection_not_found}, state}
        else
          n = length(points)
          dim = coll.dimension
          metric = coll.distance_metric
          filter_config = Keyword.get(opts, :filter_config, [])
          full_scan = Keyword.get(opts, :full_scan_threshold, @full_scan_threshold)
          coarse_thresh = Keyword.get(opts, :coarse_threshold, @coarse_threshold)

            cond do
            n <= full_scan ->
              # Do not build index; search will use brute-force (like Qdrant full_scan_threshold).
              new_state = %{state | indexes: Map.delete(state.indexes, collection_name)}
              {:reply, :ok, new_state}
            n > coarse_thresh ->
              # IVF-style: coarse quantizer only
              coarse_opts = [dimension: dim, seed: Keyword.get(opts, :seed, 0), nlist: Keyword.get(opts, :nlist)]
              coarse = CoarseQuantizer.build(points, coarse_opts)
              index_state = %{
                coarse: coarse,
                hnsw: nil,
                medoid_id: nil,
                ids: Enum.map(points, fn {id, _, _} -> id end),
                id_to_sketch: nil,
                id_to_mask: nil,
                graph: nil,
                thresholds: coarse.thresholds,
                dimension: dim,
                metric: metric,
                filter_config: filter_config
              }
              new_state = %{state | indexes: Map.put(state.indexes, collection_name, index_state)}
              {:reply, :ok, new_state}
            true ->
              # HNSW-style multi-layer graph (between full_scan_threshold and coarse_threshold)
              hnsw_opts = [
                dimension: dim,
                distance_metric: metric,
                m: Keyword.get(opts, :m, 16),
                m0: Keyword.get(opts, :m0),
                ef_construct: Keyword.get(opts, :ef_construct, 100),
                seed: Keyword.get(opts, :seed, 0),
                build_workers: Keyword.get(opts, :build_workers, 1)
              ]
              hnsw_opts = if hnsw_opts[:m0] == nil, do: Keyword.delete(hnsw_opts, :m0), else: hnsw_opts
              hnsw_opts = if hnsw_opts[:build_workers] == 1, do: Keyword.delete(hnsw_opts, :build_workers), else: hnsw_opts
              case HnswGraph.build(points, hnsw_opts) do
                {:error, reason} -> {:reply, {:error, reason}, state}
                hnsw ->
                  # EAB thresholds not used for HNSW search; store empty for compatibility
                  index_state = %{
                    coarse: nil,
                    hnsw: hnsw,
                    medoid_id: nil,
                    ids: hnsw.ids,
                    id_to_sketch: nil,
                    id_to_mask: nil,
                    graph: nil,
                    thresholds: [],
                    dimension: dim,
                    metric: metric,
                    filter_config: filter_config
                  }
                  new_state = %{state | indexes: Map.put(state.indexes, collection_name, index_state)}
                  {:reply, :ok, new_state}
              end
          end
        end
    end
  end

  def handle_call({:get_index, collection_name}, _from, state) do
    idx = Map.get(state.indexes, collection_name)
    {:reply, idx, state}
  end

  def handle_call({:get_candidates, collection_name, query_vector, ef, opts}, _from, state) do
    idx = Map.get(state.indexes, collection_name)
    result = if idx == nil do
      {:error, :no_index}
    else
      hnsw = Map.get(idx, :hnsw)
      coarse = Map.get(idx, :coarse)
      cond do
        hnsw != nil ->
          # HNSW path: full-vector search on multi-layer graph
          candidate_ids = HnswGraph.search(hnsw, query_vector, max(ef, 1))
          {:ok, candidate_ids}
        coarse != nil ->
          # IVF path: probe nprobe buckets, collect up to ef ids
          thresholds = Map.get(idx, :thresholds)
          if thresholds == nil or thresholds == [] do
            {:error, :index_needs_rebuild}
          else
            query_sketch = EAB.vector_to_sketch(query_vector, idx.thresholds, idx.dimension)
            nprobe = Keyword.get(opts, :nprobe, 8)
            bucket_ids = CoarseQuantizer.search(coarse, query_sketch, nprobe)
            candidate_ids = CoarseQuantizer.collect_ids_from_buckets(coarse, bucket_ids, max(ef, 1))
            {:ok, candidate_ids}
          end
        true ->
          # Single-layer graph path (Vamana/sketches)
          thresholds = Map.get(idx, :thresholds)
          if thresholds == nil or thresholds == [] do
            {:error, :index_needs_rebuild}
          else
            query_sketch = EAB.vector_to_sketch(query_vector, idx.thresholds, idx.dimension)
            filter = Keyword.get(opts, :filter, %{}) || %{}
            query_mask = PM.filter_to_mask(filter, idx.filter_config)
            candidate_ids = Graph.search_with_sketches(
              idx.medoid_id, query_sketch, idx.graph,
              idx.id_to_sketch, idx.id_to_mask, query_mask, ef
            )
            {:ok, candidate_ids}
          end
      end
    end
    {:reply, result, state}
  end

  def handle_call({:persist, path}, _from, state) do
    p = (path || state.data_path) |> to_string()
    payload = %{version: @index_version, indexes: state.indexes}
    File.write(p, :erlang.term_to_binary(payload))
    {:reply, :ok, state}
  rescue
    e -> {:reply, {:error, e}, state}
  end

  def handle_call({:load, path}, _from, state) do
    p = (path || state.data_path) |> to_string()
    case File.read(p) do
      {:ok, bin} ->
        try do
          payload = :erlang.binary_to_term(bin)
          new_state = load_payload(state, payload)
          {:reply, :ok, new_state}
        rescue
          _ -> {:reply, {:error, :invalid_format}, state}
        end
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp get_collection(registry, collection_name) do
    ElixDb.CollectionRegistry.get_collection(registry, collection_name)
  end

  defp ensure_list(vec) when is_list(vec), do: vec
  defp ensure_list(vec) when is_binary(vec), do: :erlang.binary_to_list(vec)
  defp ensure_list(vec), do: List.wrap(vec)

  defp load_payload(state, %{version: v, indexes: indexes}) when v == @index_version do
    %{state | indexes: indexes}
  end
  defp load_payload(state, _), do: state
end
