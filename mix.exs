defmodule ThistleTea.MixProject do
  use Mix.Project

  def project do
    [
      app: :thistle_tea,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      compilers: [:elixir_make] ++ Mix.compilers(),
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [preferred_envs: ["test.all": :test, "test.watch": :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {ThistleTea.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools, :observer, :wx]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tidewave, "~> 0.6", only: [:dev]},
      {:deps_nix,
       github: "code-supply/deps_nix", ref: "e0b8b0b0e8e541ec3ef824fe6a07e60739fdb50c", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:binary, "~> 0.0.5"},
      {:ecto_sqlite3, "~> 0.24"},
      {:group, "~> 0.2"},
      {:thousand_island, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.10", runtime: false},
      {:fine, "~> 0.1.0", runtime: false},
      {:telemetry, "~> 1.0"},
      {:bitmap, "~> 1.0"},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:canonical_tailwind, "~> 0.3.0", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "test.all": ["test --include dbc_db --include vmangos_db --include namigator_maps"],
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
