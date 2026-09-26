defmodule ThistleTea.Game.World.Loader.MapTemplateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.MapTemplate

  setup do
    table = :ets.new(:map_template_test, [:set])

    rows = [
      %{entry: 0, patch: 10, map_type: 0, script_name: ""},
      %{entry: 33, patch: 10, map_type: 1, script_name: "instance_shadowfang_keep", player_limit: 10},
      %{entry: 249, patch: 9, map_type: 1, script_name: "old_onyxia"},
      %{entry: 249, patch: 10, map_type: 2, script_name: "instance_onyxias_lair", player_limit: 40, reset_delay: 5},
      %{entry: 30, patch: 10, map_type: 3, script_name: nil}
    ]

    MapTemplate.load(rows, table)
    %{table: table}
  end

  describe "map classification" do
    test "derives dungeons, raids, and battlegrounds from map_type", %{table: table} do
      refute MapTemplate.dungeon?(table, 0)
      assert MapTemplate.dungeon?(table, 33)
      assert MapTemplate.dungeon?(table, 249)
      assert MapTemplate.non_raid_dungeon?(table, 33)
      for map <- [0, 249, 30, 999, nil], do: refute(MapTemplate.non_raid_dungeon?(table, map))
      refute MapTemplate.battleground?(table, 249)
      assert MapTemplate.battleground?(table, 30)
      assert MapTemplate.admission_policy(249, table).raid?
      assert MapTemplate.admission_policy(249, table).player_limit == 40
      assert MapTemplate.admission_policy(33, table).player_limit == 10
      refute MapTemplate.admission_policy(33, table).raid?
      assert MapTemplate.reset_days(249, table) == 5
      assert MapTemplate.reset_days(33, table) == 0
      assert MapTemplate.reset_days(999, table) == 0
    end

    test "retains the selected script name and normalizes empty names", %{table: table} do
      assert MapTemplate.instance_script_name(table, 33) == "instance_shadowfang_keep"
      assert MapTemplate.instance_script_name(table, 249) == "instance_onyxias_lair"
      assert MapTemplate.instance_script_name(table, 0) == nil
      assert MapTemplate.instance_script_name(table, 30) == nil
    end
  end

  describe "dungeons/1" do
    test "retains parent and entrance metadata from the selected patch", %{table: table} do
      rows = [
        %{
          entry: 409,
          patch: 0,
          map_type: 2,
          script_name: nil,
          parent: 230,
          map_name: "Molten Core",
          ghost_entrance_map: 0,
          ghost_entrance_x: 1.0,
          ghost_entrance_y: 2.0
        },
        %{
          entry: 409,
          patch: 1,
          map_type: 2,
          linked_zone: 2717,
          script_name: nil,
          parent: 230,
          map_name: "Molten Core",
          ghost_entrance_map: 0,
          ghost_entrance_x: 3.0,
          ghost_entrance_y: 4.0
        }
      ]

      MapTemplate.load(rows, table)
      dungeon = Map.fetch!(MapTemplate.dungeons(table), 409)
      assert dungeon.parent_map == 230
      assert dungeon.name == "Molten Core"
      assert dungeon.zone_id == 2717
      assert dungeon.ghost_entrance == {0, 3.0, 4.0}
    end
  end
end
