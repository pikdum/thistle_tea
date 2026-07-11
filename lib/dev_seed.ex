defmodule ThistleTea.DevSeed do
  @moduledoc """
  Seeds a debug playground on Programmer Isle (`.go xyz 16303.2 16318.1 69.44 451`):
  a `debug`/`debug` account with pre-leveled, spell-trained, gold-stocked
  characters for multi-session group testing, plus fast-respawning mobs —
  loot piñatas with guaranteed green drops for roll testing and level-50
  hostiles for combat and XP testing.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Network.Message.CmsgCharCreate
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding

  require Logger

  @account "debug"
  @map 451
  @spawn_point {16_303.2, 16_318.1, 69.44}
  @level 50
  @coinage 100_000_000

  @human 1
  @characters [
    {"Debugwarrior", @human, 1},
    {"Debugpaladin", @human, 2},
    {"Debugrogue", @human, 4},
    {"Debugpriest", @human, 5},
    {"Debugmage", @human, 8}
  ]

  @pinata_entry 721
  @pinata_loot %{items: [{1604, 1}, {1608, 1}, {118, 2}], gold: 10_000}
  @pinata_offsets [{6.0, 6.0}, {9.0, 3.0}, {12.0, 6.0}]
  @hostile_entry 1783
  @hostile_offsets [{-45.0, 25.0}, {-50.0, 15.0}, {-55.0, 25.0}]
  @respawn_secs 5
  @hostile_respawn_secs 30
  @base_low_guid 990_000
  @debug_equipment %{
    1 => [22_223, 11_722, 10_845, 11_703, 14_928, 12_555, 14_974, 10_165, 11_677, 12_774, 10_195, 13_022],
    2 => [22_223, 11_722, 10_845, 11_703, 14_928, 12_555, 14_974, 10_165, 11_677, 1721, 1203],
    4 => [10_187, 10_189, 12_793, 14_674, 15_057, 15_071, 13_120, 10_110, 8297, 12_791, 6660, 13_022],
    5 => [11_839, 10_172, 10_806, 14_304, 10_807, 18_697, 14_311, 10_808, 12_552, 1607],
    8 => [17_715, 10_172, 14_141, 11_662, 14_132, 18_697, 12_546, 11_634, 14_134, 19_567]
  }
  @debug_reagents %{
    4 => [{5140, 20}],
    5 => [{17_056, 20}],
    8 => [{17_056, 20}, {17_031, 20}, {17_032, 20}]
  }

  def run do
    seed_account_and_characters()
    seed_mobs()
    Logger.info("Debug seed ready: #{@account}/#{@account} on Programmer Isle (.go xyz 16303.2 16318.1 69.44 451)")
  end

  defp seed_account_and_characters do
    ThistleTea.Account.register(@account, @account)

    case ThistleTea.Account.get_user(@account) do
      {:ok, %ThistleTea.Account{id: account_id}} ->
        Enum.each(@characters, &create_character(&1, account_id))

      _ ->
        Logger.warning("Debug seed: account #{@account} missing, skipping characters")
    end
  end

  defp create_character({name, race, class}, account_id) do
    params = %CmsgCharCreate{
      name: name,
      race: race,
      class: class,
      gender: 1,
      skin_color: 0,
      face: 0,
      hair_style: 0,
      hair_color: 0,
      facial_hair: 0,
      outfit_id: 0
    }

    params
    |> CharacterLoader.build(account_id)
    |> set_level(@level)
    |> learn_class_spells()
    |> max_skills()
    |> set_coinage(@coinage)
    |> move_to_isle()
    |> Characters.create()
    |> equip_debug_gear()
  end

  defp equip_debug_gear({:ok, %Character{unit: %{class: class}} = character}) do
    character =
      character
      |> Characters.clear_equipment()
      |> Characters.assign_items(Map.get(@debug_equipment, class, []))
      |> Characters.assign_items(Map.get(@debug_reagents, class, []))
      |> Character.restore_health_and_mana()

    {:ok, CharacterStore.put(character)}
  end

  defp equip_debug_gear(result), do: result

  defp set_level(character, level) do
    case Stats.get(character.unit.race, character.unit.class, level) do
      {:ok, stats} ->
        character
        |> Stats.apply(stats)
        |> Character.sync_equipment_stats()
        |> Character.restore_health_and_mana()

      _ ->
        character
    end
  end

  defp learn_class_spells(%Character{internal: internal, unit: unit} = character) do
    existing = internal.spells || []
    new_ids = ClassSpell.trainable_spell_ids(unit.class, unit.level)
    superseded_by = SpellLoader.superseded_by_map(existing ++ new_ids)
    {all_ids, _events} = SpellBook.learn(existing, new_ids, superseded_by)

    %{character | internal: %{internal | spells: all_ids}}
  end

  defp max_skills(%Character{unit: unit, player: player, internal: internal} = character) do
    derived = SkillLoader.initial_skills(internal.spells, unit.race, unit.class, unit.level)

    skills =
      derived
      |> Map.merge(player.skills || %{})
      |> Skills.max_out()

    %{character | player: %{player | skills: skills}}
  end

  defp set_coinage(%Character{player: player} = character, coinage) do
    %{character | player: %{player | coinage: coinage}}
  end

  defp move_to_isle(%Character{movement_block: movement_block, internal: internal} = character) do
    {x, y, z} = @spawn_point

    area =
      case Pathfinding.get_zone_and_area(@map, {x, y, z}) do
        {_zone, area} -> area
        _ -> 0
      end

    %{
      character
      | movement_block: %{movement_block | position: {x, y, z, 0.0}},
        internal: %{internal | map: @map, area: area}
    }
  end

  defp seed_mobs do
    {x, y, z} = @spawn_point

    @pinata_offsets
    |> Enum.with_index()
    |> Enum.each(fn {{dx, dy}, index} ->
      spawn_mob(@pinata_entry, @base_low_guid + index, {x + dx, y + dy, z}, @pinata_loot, @respawn_secs)
    end)

    @hostile_offsets
    |> Enum.with_index()
    |> Enum.each(fn {{dx, dy}, index} ->
      spawn_mob(@hostile_entry, @base_low_guid + 100 + index, {x + dx, y + dy, z}, nil, @hostile_respawn_secs)
    end)
  end

  defp spawn_mob(entry, low_guid, {x, y, z}, loot_override, respawn_secs) do
    case Mangos.Repo.one(from(c in Mangos.Creature, where: c.id == ^entry, limit: 1, preload: [:creature_template])) do
      %Mangos.Creature{} = creature ->
        creature = %{
          creature
          | guid: low_guid,
            map: @map,
            position_x: x,
            position_y: y,
            position_z: z,
            orientation: 0.0,
            spawntimesecs: respawn_secs,
            spawndist: 0.0,
            movement_type: 0
        }

        mob =
          creature
          |> MobLoader.load_creature()
          |> Mob.build()

        mob = %{mob | internal: %{mob.internal | loot: %{mob.internal.loot | override: loot_override}}}
        MobLoader.start_mob(mob)

      _ ->
        Logger.warning("Debug seed: creature #{entry} has no spawn row, skipping")
    end
  end
end
