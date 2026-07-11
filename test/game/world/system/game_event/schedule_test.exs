defmodule ThistleTea.Game.World.System.GameEvent.ScheduleTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.System.GameEvent.Schedule
  alias ThistleTea.Game.World.System.GameEvent.Schedule.Entry

  describe "active_events/2" do
    test "returns events within their recurrence window" do
      schedule = Schedule.new([entry(1, "2026-01-01T00:00:00", "2026-01-10T00:00:00", 48, 1)])

      assert Schedule.active_events(schedule, datetime("2026-01-03T00:30:00")) == [1]
      assert Schedule.active_events(schedule, datetime("2026-01-03T01:00:00")) == []
      assert Schedule.active_events(schedule, datetime("2026-01-10T00:00:00")) == []
    end

    test "treats a duration covering the recurrence as continuously active" do
      schedule = Schedule.new([entry(1, "2026-01-01T00:00:00", "2026-01-02T00:00:00", 1, 2)])

      assert Schedule.active_events(schedule, datetime("2026-01-01T12:00:00")) == [1]
    end
  end

  describe "next_transition/2" do
    test "finds starts, stops, and the end of a continuous event" do
      recurring = Schedule.new([entry(1, "2026-01-01T00:00:00", "2026-01-10T00:00:00", 48, 1)])
      continuous = Schedule.new([entry(2, "2026-01-01T00:00:00", "2026-01-02T00:00:00", 1, 2)])

      assert Schedule.next_transition(recurring, datetime("2025-12-31T23:00:00")) ==
               datetime("2026-01-01T00:00:00")

      assert Schedule.next_transition(recurring, datetime("2026-01-03T00:30:00")) ==
               datetime("2026-01-03T01:00:00")

      assert Schedule.next_transition(recurring, datetime("2026-01-02T00:30:00")) ==
               datetime("2026-01-03T00:00:00")

      assert Schedule.next_transition(continuous, datetime("2026-01-01T12:00:00")) ==
               datetime("2026-01-02T00:00:00")
    end
  end

  defp entry(id, starts_at, ends_at, occurrence_hours, length_hours) do
    %Entry{
      id: id,
      starts_at: datetime(starts_at),
      ends_at: datetime(ends_at),
      occurrence_seconds: occurrence_hours * 60 * 60,
      length_seconds: length_hours * 60 * 60
    }
  end

  defp datetime(value) do
    value
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!("Etc/UTC")
  end
end
