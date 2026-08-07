defmodule ThistleTea.Game.World.Loader.ConditionCoverageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.ConditionCoverage

  @moduletag :vmangos_db

  test "checked-in report matches the pinned database" do
    report = ConditionCoverage.audit() |> ConditionCoverage.render()

    assert File.read!("docs/condition-coverage.md") == report
  end

  test "discovers the complete condition inventory" do
    audit = ConditionCoverage.audit()

    assert audit.direct_references == 8_388
    assert audit.root_definitions == 977
    assert MapSet.size(audit.reachable) == 1_776
    assert audit.missing == MapSet.new()
    assert audit.cycles == MapSet.new()
  end
end
