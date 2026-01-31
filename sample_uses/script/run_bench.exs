# Run from sample_uses dir: elixir script/run_bench.exs v0.2.0 [v0.1.0]
# Or from repo root: cd sample_uses && elixir script/run_bench.exs v0.2.0
# Runs each use case for the given version, collects bench_result.json, writes reports/<version>.json
# and optionally reports/<version>_vs_<prev>.md if previous version report exists or is given.

version = System.argv() |> List.first() || raise "Usage: elixir script/run_bench.exs VERSION [PREV_VERSION]"
prev_version = System.argv() |> Enum.at(1)

base_dir = if File.cwd!() =~ ~r/sample_uses$/, do: File.cwd!(), else: Path.join(File.cwd!(), "sample_uses")
reports_dir = Path.join(base_dir, "reports")
File.mkdir_p!(reports_dir)

use_cases = [
  {"01_simple_search", "SimpleSearch"},
  {"02_semantic_faq", "SemanticFaq"},
  {"03_similar_items", "SimilarItems"},
  {"04_persistence", "Persistence"}
]

defmodule RunBench do
  def run_mix(path, task, extra_args \\ []) do
    opts = [cd: path, stderr_to_stdout: true]
    {output, status} = System.cmd("mix", [task | extra_args], opts)
    {status == 0, output}
  end

  def run_bench(path, module) do
    run_mix(path, "run", ["-e", "#{module}.run_bench()"])
  end

  def read_result(path) do
    file = Path.join(path, "bench_result.json")
    case File.read(file) do
      {:ok, bin} -> decode_simple_json(bin)
      {:error, _} -> nil
    end
  end

  def decode_simple_json(bin) do
    # Parse {"key":number,...}
    Regex.scan(~r/"(\w+)":(\d+)/, bin)
    |> Map.new(fn [_, k, v] -> {k, String.to_integer(v)} end)
  end
end

defmodule ReportEncode do
  def to_json(map) when is_map(map) do
    pairs = Enum.map(map, fn {k, v} -> ~s("#{k}": #{encode_val(v)}) end)
    "{\n  " <> Enum.join(pairs, ",\n  ") <> "\n}"
  end
  defp encode_val(v) when is_map(v), do: to_json(v)
  defp encode_val(v) when is_list(v), do: "[" <> Enum.map_join(v, ", ", &encode_val/1) <> "]"
  defp encode_val(v) when is_binary(v), do: ~s("#{v}")
  defp encode_val(v) when is_integer(v), do: to_string(v)
  defp encode_val(v) when is_number(v), do: to_string(v)
  defp encode_val(nil), do: "null"
end

results = for {folder, module} <- use_cases do
  path = Path.join([base_dir, version, folder])
  unless File.dir?(path) do
    IO.puts(:stderr, "Skip (missing): #{path}")
    {folder, nil}
  else
    IO.puts("Running #{version}/#{folder}...")
    {ok, _} = RunBench.run_mix(path, "deps.get")
    unless ok, do: IO.puts(:stderr, "Warning: mix deps.get failed in #{path}")
    {ok_bench, _} = RunBench.run_bench(path, module)
    result = if ok_bench, do: RunBench.read_result(path), else: nil
    if result, do: IO.puts("  wall_us=#{result["wall_us"]} memory_bytes=#{result["memory_bytes"]}")
    {folder, result}
  end
end

use_cases_map = Enum.into(results, %{}, fn {k, v} -> {k, v} end)
report = %{
  "version" => version,
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "use_cases" => use_cases_map
}

# Write report as .term (for loading) and .json (for humans)
report_path_term = Path.join(reports_dir, "#{version}.term")
report_path_json = Path.join(reports_dir, "#{version}.json")
File.write!(report_path_term, :erlang.term_to_binary(report))
File.write!(report_path_json, ReportEncode.to_json(report))
IO.puts("Wrote #{report_path_term} and #{report_path_json}")

# Comparison report
prev = prev_version || (case version do
  "v0.2.0" -> "v0.1.0"
  "v0.3.0" -> "v0.2.0"
  _ -> nil
end)

if prev do
  prev_path = Path.join(reports_dir, "#{prev}.term")
  if File.exists?(prev_path) do
    prev_report = File.read!(prev_path) |> :erlang.binary_to_term()
    prev_uc = Map.get(prev_report, "use_cases", %{}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
    curr_uc = report["use_cases"]
    rows = for uc <- Map.keys(curr_uc) |> Enum.sort(), curr = curr_uc[uc], curr != nil, prev_data = prev_uc[uc], prev_data != nil do
      for key <- ["wall_us", "memory_bytes"] do
        a = prev_data[key] || prev_data[to_string(key)] || 0
        b = curr[key] || curr[to_string(key)] || 0
        delta = if a == 0, do: "n/a", else: "#{Float.round((b - a) / a * 100, 1)}%"
        "| #{uc} | #{key} | #{a} | #{b} | #{delta} |"
      end
    end |> List.flatten()
    lines = [
      "# #{version} vs #{prev}",
      "",
      "| Use case | Metric | #{prev} | #{version} | Delta |",
      "|----------|--------|--------|--------|-------|"
    ] ++ rows
    comp_path = Path.join(reports_dir, "#{version}_vs_#{prev}.md")
    File.write!(comp_path, Enum.join(lines, "\n"))
    IO.puts("Wrote #{comp_path}")
  end
end
