defmodule ThistleTea.Game.World.System.GameEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.GameEvent.Schedule
  alias ThistleTea.Game.World.System.GameEvent.Schedule.Entry

  describe "start_link/1" do
    test "activates the current schedule and applies its next transition" do
      parent = self()
      now = ~U[2026-01-01 00:00:01.900000Z]
      clock = start_supervised!({Agent, fn -> now end})

      schedule =
        Schedule.new([
          %Entry{
            id: 9,
            starts_at: ~U[2026-01-01 00:00:00Z],
            ends_at: ~U[2026-01-01 00:00:06Z],
            occurrence_seconds: 60,
            length_seconds: 2
          }
        ])

      name = String.to_atom("game_event_test_#{System.unique_integer([:positive])}")

      start_supervised!(
        {GameEvent,
         name: name,
         schedule: schedule,
         now: fn -> Agent.get(clock, & &1) end,
         on_change: fn new_events, old_events -> send(parent, {:changed, new_events, old_events}) end}
      )

      assert_receive {:changed, %MapSet{} = active, %MapSet{} = previous}
      assert active == MapSet.new([9])
      assert previous == MapSet.new()
      assert GameEvent.get_events(name) == [9]
      assert GameEvent.active_events(name) == [9]

      assert %{active: [active_entry], next: next} = GameEvent.status(name)
      assert active_entry.id == 9
      assert next.stops == [active_entry]
      assert next.starts == []
      assert next.at == ~U[2026-01-01 00:00:02Z]

      Agent.update(clock, fn _ -> next.at end)
      assert_receive {:changed, %MapSet{} = inactive, %MapSet{} = active}, 1_500
      assert inactive == MapSet.new()
      assert active == MapSet.new([9])
      assert GameEvent.get_events(name) == []
      assert GameEvent.active_events(name) == []
    end
  end

  describe "set_active/3" do
    test "publishes before notifying owners and preserves unrelated active events" do
      parent = self()
      name = String.to_atom("game_event_test_#{System.unique_integer([:positive])}")

      entries =
        for id <- [2, 7] do
          %Entry{
            id: id,
            starts_at: ~U[2026-01-01 00:00:00Z],
            ends_at: ~U[2026-01-02 00:00:00Z],
            occurrence_seconds: 3_600,
            length_seconds: 1_800
          }
        end

      start_supervised!(
        {GameEvent,
         name: name,
         schedule: Schedule.new(entries),
         now: fn -> ~U[2026-01-01 00:00:00Z] end,
         on_change: fn _new, _old -> send(parent, {:published, GameEvent.active_events(name)}) end}
      )

      assert_receive {:published, [2, 7]}
      assert GameEvent.set_active(2, false, name) == :ok
      assert_receive {:published, [7]}
      assert GameEvent.get_events(name) == [7]
      assert GameEvent.set_active(2, true, name) == :ok
      assert_receive {:published, [2, 7]}
      assert GameEvent.set_active(2, true, name) == :ok
      assert GameEvent.set_active(99, true, name) == {:error, :unknown_event}
      refute_receive {:published, _}
      assert GameEvent.active_events(name) == [2, 7]
      stop_supervised(GameEvent)
      assert GameEvent.active_events(name) == []
    end
  end
end
