defmodule ThistleTea.Game.World.Loader.GameEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.GameEvent, as: GameEventRow
  alias ThistleTea.Game.World.Loader.GameEvent

  describe "from_rows/1" do
    test "translates VMangos minute fields into a schedule" do
      schedule =
        GameEvent.from_rows([
          %GameEventRow{
            entry: 2,
            start_time: ~N[2020-12-16 23:00:00],
            end_time: ~N[2037-12-31 23:59:59],
            occurrence: 525_600,
            length: 25_980,
            description: "Feast of Winter Veil"
          }
        ])

      assert [entry] = schedule.entries
      assert entry.id == 2
      assert entry.occurrence_seconds == 31_536_000
      assert entry.length_seconds == 1_558_800
      assert entry.description == "Feast of Winter Veil"
    end
  end

  describe "load_schedule/0" do
    @tag :vmangos_db
    test "loads only schedulable events for the supported patch" do
      schedule = GameEvent.load_schedule()

      assert schedule.entries != []
      assert Enum.all?(schedule.entries, &(&1.id not in [4, 13, 17]))
      assert Enum.any?(schedule.entries, &(&1.id == 103))
    end
  end
end
