defmodule ThistleTea.Game.Entity.Logic.AI.TickPlanTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.AI.TickPlan
  alias ThistleTea.Game.Entity.Logic.AI.TickPlan.Wake

  describe "next/2" do
    test "selects the earliest semantic deadline" do
      plan =
        TickPlan.new(1_000)
        |> TickPlan.schedule_in(:behavior, 500)
        |> TickPlan.schedule_at(:aura, 1_200)
        |> TickPlan.schedule_in(:regen, 1_000)

      assert %Wake{at: 1_200, source: :aura} = TickPlan.next(plan)
      assert TickPlan.delay(plan) == 200
    end

    test "uses a default wake only when no system has a deadline" do
      plan = TickPlan.new(1_000)

      assert %Wake{at: 1_250, source: :default} = TickPlan.next(plan, 250)
      assert TickPlan.delay(plan, 250) == 250
    end

    test "clamps overdue deadlines to an immediate wake" do
      plan = TickPlan.new(1_000) |> TickPlan.schedule_at(:aura, 900)

      assert TickPlan.delay(plan) == 0
    end
  end
end
