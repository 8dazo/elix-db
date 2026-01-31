defmodule Persistence.MixProject do
  use Mix.Project

  def project do
    [
      app: :persistence,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :elix_db]
    ]
  end

  defp deps do
    [
      {:elix_db, "~> 0.2.0"}
    ]
  end
end
