defmodule ThistleTea.Game.World.Loader.BattlegroundVMangosTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader

  @moduletag :vmangos_db

  test "pins the WSG template, battlemasters, and event-controlled spawns" do
    table = :ets.new(:battleground_vmangos_test, [:set, :public])

    templates = Mangos.Repo.all(from(row in Mangos.BattlegroundTemplate, where: row.id == 2 and row.patch <= 10))
    battlemasters = Mangos.Repo.all(from(row in Mangos.BattlemasterEntry, where: row.bg_template == 2))

    game_objects =
      Mangos.Repo.all(
        from(bg in Mangos.GameObjectBattleground,
          join: object in Mangos.GameObject,
          on: object.guid == bg.guid,
          where: object.map == 489,
          select: %{
            map: object.map,
            event1: bg.event1,
            event2: bg.event2,
            kind: :game_object,
            db_guid: object.guid,
            entry: object.id
          }
        )
      )

    creatures =
      Mangos.Repo.all(
        from(bg in Mangos.CreatureBattleground,
          join: creature in Mangos.Creature,
          on: creature.guid == bg.guid,
          where: creature.map == 489,
          select: %{
            map: creature.map,
            event1: bg.event1,
            event2: bg.event2,
            kind: :creature,
            db_guid: creature.guid,
            entry: creature.id
          }
        )
      )

    spirit_guides =
      Mangos.Repo.all(
        from(template in Mangos.CreatureTemplate,
          where: template.entry in [13_116, 13_117]
        )
      )

    safe_locs = %{
      769 => %{location_x: 1_519.530_273_437_5, location_y: 1_481.868_408_203_125, location_z: 352.023_742_675_781_25},
      770 => %{
        location_x: 933.331_481_933_593_8,
        location_y: 1_433.723_999_023_437_5,
        location_z: 345.535_675_048_828_1
      }
    }

    assert :ok = BattlegroundLoader.load(templates, safe_locs, battlemasters, game_objects ++ creatures, table)

    assert %Template{
             min_players_per_team: 4,
             max_players_per_team: 10,
             min_level: 10,
             max_level: 60,
             alliance_win_spell: 24_951,
             alliance_lose_spell: 24_950
           } = BattlegroundLoader.template_for_map(489, table)

    assert length(battlemasters) == 8
    assert BattlegroundLoader.base_flag_db_guid(:alliance, table) == 90_000
    assert BattlegroundLoader.base_flag_db_guid(:horde, table) == 90_001
    assert length(BattlegroundLoader.gate_entries(table)) == 6
    assert BattlegroundLoader.ghost_gate_db_guids(table) == [90_064, 90_065, 90_066, 90_067]
    assert BattlegroundLoader.ghost_gate_entries(table) == [180_322]
    assert BattlegroundLoader.spirit_guide_entries(table) == [13_116, 13_117]
    assert Enum.map(spirit_guides, & &1.entry) |> Enum.sort() == [13_116, 13_117]
    assert Enum.all?(spirit_guides, &(Bitwise.band(&1.extra_flags, 0x00000002) != 0))
  end
end
