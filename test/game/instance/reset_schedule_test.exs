defmodule ThistleTea.Game.Instance.ResetScheduleTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Instance.ResetSchedule

  describe "new/2" do
    test "aligns three, five, and seven day periods to 04:00 UTC" do
      now = DateTime.to_unix(~U[2026-09-23 22:00:00Z])

      for {days, date} <- [{3, ~U[2026-09-26 04:00:00Z]}, {5, ~U[2026-09-28 04:00:00Z]}, {7, ~U[2026-09-30 04:00:00Z]}] do
        assert ResetSchedule.new(days, now).deadline == DateTime.to_unix(date)
      end
    end
  end

  describe "advance/2" do
    test "skips missed periods without drifting the reset hour" do
      schedule = ResetSchedule.new(3, 0)
      assert ResetSchedule.advance(schedule, schedule.deadline - 1) == schedule
      assert ResetSchedule.advance(schedule, schedule.deadline).deadline == schedule.deadline + schedule.period

      assert ResetSchedule.advance(schedule, schedule.deadline + 2 * schedule.period + 1).deadline ==
               schedule.deadline + 3 * schedule.period
    end
  end
end
