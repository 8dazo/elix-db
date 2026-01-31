defmodule ElixDb.MixProject do
  use Mix.Project

  @source_url "https://github.com/8dazo/elix-db"
  @version "0.3.0"

  def project do
    [
      app: :elix_db,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "ElixDb",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  defp description do
    "Elixir vector database: collections, points (upsert/get/delete), exact k-NN (cosine, L2, dot product), optional DAZO index (HNSW-style + IVF), Nx batch re-rank, file persistence, and optional HTTP API."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/elix_db/CHANGELOG.md"
      },
      files: ~w(lib priv .formatter.exs mix.exs mix.lock README.md LICENSE CHANGELOG.md)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ElixDb.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.10"},
      {:plug, "~> 1.16"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
