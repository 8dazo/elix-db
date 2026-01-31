defmodule ElixDb.Metrics do
  @moduledoc """
  Simple operation timing: record latencies and compute mean, p50, p99.
  """
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  def record(server \\ __MODULE__, operation, duration_us) when is_atom(operation) and is_number(duration_us) do
    GenServer.cast(server, {:record, operation, duration_us})
  end

  def report(server \\ __MODULE__) do
    GenServer.call(server, :report)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:record, op, duration_us}, state) do
    list = Map.get(state, op, [])
    new_list = [duration_us | list] |> Enum.take(10_000)
    {:noreply, Map.put(state, op, new_list)}
  end

  @impl true
  def handle_call(:report, _from, state) do
    report =
      Enum.map(state, fn {op, list} ->
        if list == [] do
          {op, %{count: 0, mean_us: nil, p50_us: nil, p99_us: nil}}
        else
          sorted = Enum.sort(list)
          n = length(sorted)
          mean = Enum.sum(sorted) / n
          p50 = Enum.at(sorted, div(n * 50, 100))
          p99 = Enum.at(sorted, div(n * 99, 100))
          {op, %{count: n, mean_us: mean, p50_us: p50, p99_us: p99}}
        end
      end)
      |> Map.new()
    {:reply, report, state}
  end
end
