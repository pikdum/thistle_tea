defmodule ThistleTea.Game.World.Loader.CreatureEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.CreatureEvent

  describe "select_patches/1" do
    test "keeps the latest patch independently for each spawn and event" do
      rows = [
        %{guid: 1, event: 2, patch: 0, spell_start: 0},
        %{guid: 1, event: 2, patch: 6, spell_start: 71},
        %{guid: 1, event: 7, patch: 0, spell_start: 72},
        %{guid: 2, event: 2, patch: 0, spell_start: 73}
      ]

      assert CreatureEvent.select_patches(rows) == Enum.drop(rows, 1)
    end
  end

  describe "rows/0" do
    @tag :vmangos_db
    test "loads current Pyrewood, night patrol, and Winter Veil definitions" do
      rows = CreatureEvent.rows()
      assert Enum.all?(rows, &(&1.patch <= 10))
      assert length(rows) == length(Enum.uniq_by(rows, &{&1.guid, &1.event}))
      assert Enum.find(rows, &(&1.guid == 57_461 and &1.event == 49)).entry_id == 1892
      assert Enum.find(rows, &(&1.guid == 12_088 and &1.event == 27)).equipment_id == 50_001
      assert %{patch: 6, spell_start: 26_231} = Enum.find(rows, &(&1.guid == 45_829 and &1.event == 2))
    end
  end
end
