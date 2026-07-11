defmodule ThistleTea.Game.World.System.GameEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.GameEvent.Schedule
  alias ThistleTea.Game.World.System.GameEvent.Schedule.Entry

  describe "start_link/1" do
    test "activates the current schedule and applies its next transition" do
      parent = self()
      now = DateTime.utc_now()

      schedule =
        Schedule.new([
          %Entry{
            id: 9,
            starts_at: DateTime.add(now, -1, :second),
            ends_at: DateTime.add(now, 5, :second),
            occurrence_seconds: 60,
            length_seconds: 2
          }
        ])

      name = String.to_atom("game_event_test_#{System.unique_integer([:positive])}")

      start_supervised!(
        {GameEvent,
         name: name,
         schedule: schedule,
         on_change: fn new_events, old_events -> send(parent, {:changed, new_events, old_events}) end}
      )

      assert_receive {:changed, %MapSet{} = active, %MapSet{} = previous}
      assert active == MapSet.new([9])
      assert previous == MapSet.new()
      assert GameEvent.get_events(name) == [9]

      assert %{active: [active_entry], next: next} = GameEvent.status(name)
      assert active_entry.id == 9
      assert next.stops == [active_entry]
      assert next.starts == []

      assert_receive {:changed, %MapSet{} = inactive, %MapSet{} = active}, 1_500
      assert inactive == MapSet.new()
      assert active == MapSet.new([9])
    end
  end
end
