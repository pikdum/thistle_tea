defmodule ThistleTea.MixProject do
  use Mix.Project

  def project do
    [
      app: :thistle_tea,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
      # listeners: [Phoenix.CodeReloader]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ThistleTea.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:binary, "~> 0.0.5"},
      {:ecto_sqlite3, "~> 0.17"},
      {:memento, "~> 0.4.0"},
      {:thousand_island, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:telemetry, "~> 1.0"},
      {:bitmap, "~> 1.0"},
      {:rustler, "~> 0.35.0"},
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:tailwind_formatter,
       github: "100phlecs/tailwind_formatter",
       ref: "002b45269e69036b3a028cfd94d77b78c8a8a0ad",
       only: [:dev, :test],
       runtime: false},
      {:nx, "~> 0.9.1"},
      {:evision, "~> 0.2.9"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind thistle_tea", "esbuild thistle_tea"],
      "assets.deploy": [
        "tailwind thistle_tea --minify",
        "esbuild thistle_tea --minify",
        "phx.digest"
      ]
    ]
  end
end
