defmodule ElixDb.CollectionRegistry do
  @moduledoc """
  GenServer-backed registry for collection configs. Stores collection name -> Collection struct.
  """
  use GenServer

  @allowed_metrics [:cosine, :l2]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  def create_collection(server \\ __MODULE__, name, dimension, metric)
      when is_binary(name) and is_integer(dimension) do
    cond do
      dimension < 1 -> {:error, :invalid_dimension}
      metric not in @allowed_metrics -> {:error, {:invalid_metric, metric}}
      true -> GenServer.call(server, {:create, name, dimension, metric})
    end
  end

  def list_collections(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  def get_collection(server \\ __MODULE__, name) do
    GenServer.call(server, {:get, name})
  end

  def delete_collection(server \\ __MODULE__, name) do
    GenServer.call(server, {:delete, name})
  end

  @impl true
  def handle_call({:create, name, dimension, metric}, _from, state) do
    if Map.has_key?(state, name) do
      {:reply, {:error, :already_exists}, state}
    else
      collection = %ElixDb.Collection{
        name: name,
        dimension: dimension,
        distance_metric: metric
      }
      {:reply, {:ok, collection}, Map.put(state, name, collection)}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state), state}
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    {:reply, Map.get(state, name), state}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) do
    case Map.pop(state, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_coll, new_state} -> {:reply, :ok, new_state}
    end
  end
end
