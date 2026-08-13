defmodule ThistleTea.Game.World.Loader.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader

  setup do
    table = :ets.new(:battleground_loader_test, [:set, :public])
    %{table: table}
  end

  describe "load/5" do
    test "keeps the latest supported template and indexes battlemasters and event spawns", %{table: table} do
      templates = [template(patch: 4, min_players_per_team: 2), template(patch: 6, min_players_per_team: 4)]

      safe_locs = %{
        769 => %{location_x: 1.0, location_y: 2.0, location_z: 3.0},
        770 => %{location_x: 4.0, location_y: 5.0, location_z: 6.0},
        771 => %{location_x: 7.0, location_y: 8.0, location_z: 9.0},
        772 => %{location_x: 10.0, location_y: 11.0, location_z: 12.0}
      }

      battlemasters = [%Mangos.BattlemasterEntry{entry: 2_302, bg_template: 2}]

      members = [
        %{map: 489, event1: 0, event2: 0, kind: :game_object, db_guid: 90_000, entry: 179_830},
        %{map: 489, event1: 1, event2: 0, kind: :game_object, db_guid: 90_001, entry: 179_831},
        %{map: 489, event1: 2, event2: 0, kind: :creature, db_guid: 150_000, entry: 13_116},
        %{map: 489, event1: 253, event2: 0, kind: :game_object, db_guid: 90_064, entry: 180_322},
        %{map: 489, event1: 254, event2: 0, kind: :game_object, db_guid: 90_008, entry: 179_918}
      ]

      assert :ok = BattlegroundLoader.load(templates, safe_locs, battlemasters, members, table)

      assert %Template{type_id: 2, map_id: 489, min_players_per_team: 4} =
               loaded = BattlegroundLoader.template_for_map(489, table)

      assert loaded.alliance_start == {1.0, 2.0, 3.0, 0.0}
      assert loaded.horde_start == {4.0, 5.0, 6.0, 0.0}
      assert loaded.alliance_graveyard == {7.0, 8.0, 9.0, 0.0}
      assert loaded.horde_graveyard == {10.0, 11.0, 12.0, 0.0}

      assert BattlegroundLoader.template_for_battlemaster(2_302, table) ==
               BattlegroundLoader.template_for_type(2, table)

      assert BattlegroundLoader.base_flag_db_guid(:alliance, table) == 90_000
      assert BattlegroundLoader.base_flag_db_guid(:horde, table) == 90_001
      assert BattlegroundLoader.gate_entries(table) == [179_918]
      assert BattlegroundLoader.ghost_gate_db_guids(table) == [90_064]
      assert BattlegroundLoader.ghost_gate_entries(table) == [180_322]
      assert BattlegroundLoader.spirit_guide_entries(table) == [13_116]
    end
  end

  defp template(overrides) do
    defaults = %Mangos.BattlegroundTemplate{
      id: 2,
      patch: 6,
      min_players_per_team: 4,
      max_players_per_team: 10,
      min_level: 10,
      max_level: 60,
      alliance_win_spell: 24_951,
      alliance_lose_spell: 24_950,
      horde_win_spell: 24_951,
      horde_lose_spell: 24_950,
      alliance_start_location: 769,
      horde_start_location: 770,
      player_loot_id: 0
    }

    struct(defaults, overrides)
  end
end
