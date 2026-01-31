defmodule ElixDb.HttpRouter do
  @moduledoc """
  HTTP API for elix-db: collections and points (create, list, upsert, search, get, delete).
  """
  use Plug.Router
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  def init(opts), do: opts

  # GET /openapi.json
  get "/openapi.json" do
    path = Path.join(:code.priv_dir(:elix_db), "openapi.json")
    body = File.read!(path)
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  # GET /health
  get "/health" do
    status = %{status: "ok", store: Process.whereis(ElixDb.Store) != nil, registry: Process.whereis(ElixDb.CollectionRegistry) != nil}
    send_resp(conn, 200, Jason.encode!(status))
  end

  # POST /collections
  post "/collections" do
    case conn.body_params do
      %{"name" => name, "dimension" => dim, "distance_metric" => metric}
        when is_binary(name) and is_integer(dim) ->
        metric_atom = parse_metric(metric)
        case ElixDb.CollectionRegistry.create_collection(ElixDb.CollectionRegistry, name, dim, metric_atom) do
          {:ok, _} -> send_resp(conn, 201, Jason.encode!(%{ok: true}))
          {:error, :already_exists} -> send_resp(conn, 409, Jason.encode!(%{error: "collection already exists"}))
          {:error, reason} -> send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
        end
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "body must have name, dimension, distance_metric"}))
    end
  end

  # GET /collections
  get "/collections" do
    list = ElixDb.CollectionRegistry.list_collections(ElixDb.CollectionRegistry)
    body = Enum.map(list, fn c -> %{name: c.name, dimension: c.dimension, distance_metric: c.distance_metric} end)
    send_resp(conn, 200, Jason.encode!(body))
  end

  # GET /collections/:name
  get "/collections/:name" do
    name = conn.path_params["name"]
    case ElixDb.CollectionRegistry.get_collection(ElixDb.CollectionRegistry, name) do
      nil -> send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      coll -> send_resp(conn, 200, Jason.encode!(%{name: coll.name, dimension: coll.dimension, distance_metric: coll.distance_metric}))
    end
  end

  # DELETE /collections/:name
  delete "/collections/:name" do
    name = conn.path_params["name"]
    case ElixDb.CollectionRegistry.delete_collection(ElixDb.CollectionRegistry, name) do
      :ok -> send_resp(conn, 200, Jason.encode!(%{ok: true}))
      {:error, :not_found} -> send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
    end
  end

  # POST /collections/:name/points/batch
  post "/collections/:name/points/batch" do
    name = conn.path_params["name"]
    case conn.body_params do
      %{"points" => points} when is_list(points) ->
        parsed = Enum.map(points, fn p ->
          id = p["id"]
          vec = (p["vector"] || []) |> Enum.map(&maybe_float/1)
          payload = Map.get(p, "payload", %{})
          {id, vec, payload}
        end)
        case ElixDb.Store.upsert_batch(ElixDb.Store, name, parsed) do
          :ok -> send_resp(conn, 200, Jason.encode!(%{ok: true}))
          {:error, reason} -> send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
        end
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "body must have points (array of {id, vector, payload?})"}))
    end
  end

  # PUT /collections/:name/points
  put "/collections/:name/points" do
    name = conn.path_params["name"]
    case conn.body_params do
      %{"id" => id, "vector" => vec} ->
        payload = Map.get(conn.body_params, "payload", %{})
        vec_list = Enum.map(vec, &maybe_float/1)
        case ElixDb.Store.upsert(ElixDb.Store, name, id, vec_list, payload) do
          :ok -> send_resp(conn, 200, Jason.encode!(%{ok: true}))
          {:error, reason} -> send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
        end
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "body must have id and vector"}))
    end
  end

  # POST /collections/:name/points/search
  post "/collections/:name/points/search" do
    name = conn.path_params["name"]
    case conn.body_params do
      %{"vector" => vec} ->
        k = Map.get(conn.body_params, "k", 10)
        vec_list = Enum.map(vec, &maybe_float/1)
        opts = search_opts_from_body(conn.body_params)
        case ElixDb.Store.search(ElixDb.Store, name, vec_list, k, opts) do
          {:ok, results} -> send_resp(conn, 200, Jason.encode!(%{results: results}))
          {:error, reason} -> send_resp(conn, 400, Jason.encode!(%{error: inspect(reason)}))
        end
      _ -> send_resp(conn, 400, Jason.encode!(%{error: "body must have vector"}))
    end
  end

  # GET /collections/:name/points/:id
  get "/collections/:name/points/:id" do
    name = conn.path_params["name"]
    id = conn.path_params["id"]
    case ElixDb.Store.get(ElixDb.Store, name, id) do
      nil -> send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
      point -> send_resp(conn, 200, Jason.encode!(point))
    end
  end

  # DELETE /collections/:name/points/:id
  delete "/collections/:name/points/:id" do
    name = conn.path_params["name"]
    id = conn.path_params["id"]
    ElixDb.Store.delete(ElixDb.Store, name, id)
    send_resp(conn, 200, Jason.encode!(%{ok: true}))
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
  end

  defp parse_metric("cosine"), do: :cosine
  defp parse_metric("dot_product"), do: :dot_product
  defp parse_metric("l2"), do: :l2
  defp parse_metric(_), do: :cosine

  defp search_opts_from_body(body) do
    opts = []
    opts = if Map.has_key?(body, "filter") and is_map(body["filter"]), do: Keyword.put(opts, :filter, body["filter"]), else: opts
    opts = if Map.has_key?(body, "score_threshold"), do: Keyword.put(opts, :score_threshold, maybe_float(body["score_threshold"])), else: opts
    opts = if Map.has_key?(body, "distance_threshold"), do: Keyword.put(opts, :distance_threshold, maybe_float(body["distance_threshold"])), else: opts
    opts = if Map.has_key?(body, "with_payload"), do: Keyword.put(opts, :with_payload, body["with_payload"]), else: opts
    opts = if Map.has_key?(body, "with_vector"), do: Keyword.put(opts, :with_vector, body["with_vector"]), else: opts
    opts
  end

  defp maybe_float(n) when is_number(n), do: n * 1.0
  defp maybe_float(n), do: String.to_float(to_string(n))
end
