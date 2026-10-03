defmodule ThistleTea.Game.World.Loader.GameEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.GameEvent, as: GameEventRow
  alias ThistleTea.Game.Core.GameEvent.DarkmoonFaire
  alias ThistleTea.Game.Core.GameEvent.DragonsOfNightmare
  alias ThistleTea.Game.Core.GameEvent.FireworksShow
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

    test "hands hardcoded events to their rule and drops those without one" do
      schedule =
        GameEvent.from_rows([
          %GameEventRow{entry: 4, hardcoded: 1, description: "Darkmoon Faire (Elwynn)"},
          %GameEventRow{entry: 13, hardcoded: 1, description: "Elemental Invasion"}
        ])

      assert [%{id: 4, rule: DarkmoonFaire, description: "Darkmoon Faire (Elwynn)"}] = schedule.entries
    end
  end

  describe "load_schedule/0" do
    @tag :vmangos_db
    test "loads only schedulable events for the supported patch" do
      schedule = GameEvent.load_schedule()

      assert schedule.entries != []
      assert Enum.all?(schedule.entries, &(&1.id not in [13, 17]))
      assert Enum.any?(schedule.entries, &(&1.id == 103))
      assert [4, 5, 23, 24] == for(%{rule: DarkmoonFaire, id: id} <- schedule.entries, do: id)
      assert [6, 39] == for(%{rule: FireworksShow, id: id} <- schedule.entries, do: id)
      assert [66] == for(%{rule: DragonsOfNightmare, id: id} <- schedule.entries, do: id)
      assert Enum.any?(schedule.entries, &(&1.id == 34))
    end
  end
end
