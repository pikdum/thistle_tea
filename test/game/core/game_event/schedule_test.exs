defmodule ThistleTea.Game.Core.GameEvent.ScheduleTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.DarkmoonFaire
  alias ThistleTea.Game.Core.GameEvent.DragonsOfNightmare
  alias ThistleTea.Game.Core.GameEvent.FireworksShow
  alias ThistleTea.Game.Core.GameEvent.Schedule
  alias ThistleTea.Game.Core.GameEvent.Schedule.Entry

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

  describe "rule entries" do
    test "follow their rule's calendar" do
      schedule = Schedule.new([%Entry{id: 4, rule: DarkmoonFaire}, %Entry{id: 23, rule: DarkmoonFaire}])

      assert Schedule.active_events(schedule, datetime("2026-10-04T23:59:59")) == [23]
      assert Schedule.active_events(schedule, datetime("2026-10-05T00:00:00")) == [4]
    end

    test "change at the next midnight their rule disagrees with today" do
      schedule = Schedule.new([%Entry{id: 4, rule: DarkmoonFaire}])

      assert Schedule.next_transition(schedule, datetime("2026-10-02T13:00:00")) == datetime("2026-10-05T00:00:00")
      assert Schedule.next_transition(schedule, datetime("2026-10-06T13:00:00")) == datetime("2026-10-12T00:00:00")
      assert Schedule.next_transition(schedule, datetime("2026-10-12T13:00:00")) == datetime("2026-12-07T00:00:00")
    end

    test "keep the dragons of Nightmare out for the life of the world" do
      schedule = Schedule.new([%Entry{id: 66, rule: DragonsOfNightmare}])

      assert Schedule.active_events(schedule, datetime("2026-10-03T12:00:00")) == [66]
      assert Schedule.next_transition(schedule, datetime("2026-10-03T12:00:00")) == nil
    end

    test "follow the database-scheduled events active at the moment" do
      new_year = entry(34, "2026-12-31T06:00:00", "2027-01-02T06:00:00", 24 * 365, 24)
      schedule = Schedule.new([new_year, %Entry{id: 6, rule: FireworksShow}, %Entry{id: 39, rule: FireworksShow}])

      assert Schedule.active_events(schedule, datetime("2026-12-31T05:05:00")) == []
      assert Schedule.active_events(schedule, datetime("2026-12-31T06:05:00")) == [6, 34]
      assert Schedule.active_events(schedule, datetime("2026-12-31T06:15:00")) == [34, 39]
      assert Schedule.next_transition(schedule, datetime("2026-12-31T05:05:00")) == datetime("2026-12-31T06:00:00")
      assert Schedule.next_transition(schedule, datetime("2026-12-31T06:15:00")) == datetime("2026-12-31T06:21:00")
      assert Schedule.next_transition(schedule, datetime("2026-12-31T06:21:00")) == datetime("2026-12-31T18:00:00")
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
