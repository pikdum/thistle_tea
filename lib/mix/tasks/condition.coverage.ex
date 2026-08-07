defmodule Mix.Tasks.Condition.Coverage do
  @shortdoc "Writes or verifies VMangos condition coverage"
  @moduledoc """
  Writes or verifies the VMangos condition coverage report.

      mix condition.coverage
      mix condition.coverage --check
  """
  use Mix.Task

  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.World.Loader.ConditionCoverage

  @report_path "docs/condition-coverage.md"

  @impl Mix.Task
  def run(args) do
    start_repo()
    report = ConditionCoverage.audit() |> ConditionCoverage.render()

    if "--check" in args do
      verify!(report)
    else
      File.write!(@report_path, report)
      Mix.shell().info("Wrote #{@report_path}")
    end
  end

  defp start_repo do
    {:ok, _applications} = Application.ensure_all_started(:ecto_sqlite3)

    case Repo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp verify!(report) do
    if File.read(@report_path) == {:ok, report} do
      Mix.shell().info("#{@report_path} is current")
    else
      Mix.raise("#{@report_path} is stale; run mix condition.coverage")
    end
  end
end
