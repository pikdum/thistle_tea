defmodule ThistleTea.MixProject do
  use Mix.Project

  def project do
    [
      app: :thistle_tea,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ThistleTea.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:binary, "~> 0.0.5"},
      {:ecto_sqlite3, "~> 0.16"},
      {:thousand_island, "~> 1.0"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
