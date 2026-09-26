defmodule ThistleTea.DevSeed do
  @moduledoc """
  Seeds a debug playground on Programmer Isle (`.go xyz 16303.2 16318.1 69.44 451`):
  a `debug`/`debug` account with pre-leveled, spell-trained, gold-stocked
  characters for multi-session group testing. Separate `debugbuyer/debugbuyer`
  and `debugbidder/debugbidder` accounts support auction and trade acceptance.
  The `debugrival/debugrival` account has an Orc warrior for opposing-faction testing.
  The playground also has fast-respawning mobs —
  loot piñatas with guaranteed green drops for roll testing, level-50
  hostiles for combat and XP testing, and a Devilsaur (combat reach 5.0)
  for big-hitbox spell-range testing, a Defias Thug for pickpocketing, and a
  Stonetusk Boar with a three-minute respawn for skinning practice. A Prairie
  Wolf Alpha and Mottled Worg support pet ability discovery and training, with
  Belia Thundergranite for pet untraining, Einris Brightspear for talent resets,
  and Jenova Stoneshield for stabling. A repair
  vendor and spirit healer support equipment wear and resurrection testing.
  Two copies of Plugger Spazzring support limited-stock merchant testing.
  A door, lever, incantation, mortar, and stink bombs support object use and activation spells.
  A Land Walker supports Zorbin's Ultra-Shrinker and creature transformation testing.
  An isolated Salia at {16203.2, 16318.1} supports incoming player charm and AI testing.
  A Squirrel drops random-property cloth armor and has a three-minute respawn for loot testing.
  Three adjacent Skeletal Flayers west of the playground support chained spell testing.
  Six closely grouped Prairie Wolf Alphas farther west support area target-limit testing.
  A Highperch Soarer circles above the northeast field, alongside a stationary
  Bloodseeker Bat, for flight, corpse landing, and respawn testing.
  Two Horde Laborers east of the playground retain their low-health assistance
  event, with their initial aggro shout disabled, to isolate retreat and recruitment.
  Marisa du'Paige northeast of the playground retains her root-and-retreat spells.
  A stationary Rockjaw Trogg and wandering Burly Rockjaw Trogg farther north
  support fleeing-faction help alarms without initial assistance recruitment.
  A Defias Evoker southeast of the playground supports controlled ground spell casts.
  A Stormwind guard and Skeletal Flayer southwest of the playground support
  NPC-assisted kills, contribution-based experience, and loot eligibility.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.DevSeed.ActionBars
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Network.Message.CmsgCharCreate
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.Player.Stats
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.PetLevel, as: PetLevelLoader
  alias ThistleTea.Game.World.Loader.Skill, as: SkillLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.WorldRef

  require Logger

  @account "debug"
  @map 451
  @spawn_point {16_303.2, 16_318.1, 69.44}
  @level 50
  @coinage 100_000_000
  @pet_training_spells [5149, 4195, 4196, 23_100, 23_111, 24_547, 24_440, 2980]

  @human 1
  @orc 2
  @dwarf 3
  @night_elf 4
  @characters [
    {"Debugwarrior", @human, 1},
    {"Debugpaladin", @human, 2},
    {"Debugrogue", @human, 4},
    {"Debugpriest", @human, 5},
    {"Debugmage", @human, 8},
    {"Debugwarlock", @human, 9},
    {"Debughunter", @dwarf, 3},
    {"Debugshaman", @orc, 7},
    {"Debugdruid", @night_elf, 11}
  ]

  @pinata_entry 721
  @pinata_loot %{items: [{1604, 1}, {1608, 1}, {118, 2}], gold: 10_000}
  @pinata_offsets [{6.0, 6.0}, {9.0, 3.0}, {12.0, 6.0}]
  @hostile_entry 1783
  @hostile_offsets [{-45.0, 25.0}, {-50.0, 15.0}, {-55.0, 25.0}]
  @devilsaur_entry 6498
  @devilsaur_offset {-70.0, -25.0}
  @pickpocket_entry 38
  @pickpocket_offset {25.0, -20.0}
  @respawn_secs 5
  @hostile_respawn_secs 30
  @base_low_guid 990_000
  @debug_equipment %{
    1 => [22_223, 11_722, 10_845, 11_703, 14_928, 12_555, 14_974, 10_165, 11_677, 12_774, 10_195, 13_022],
    2 => [22_223, 11_722, 10_845, 11_703, 14_928, 12_555, 14_974, 10_165, 11_677, 1721, 1203],
    3 => [10_187, 10_189, 12_793, 14_674, 15_057, 15_071, 13_120, 10_110, 8297, 12_791, 6660, 2825, 18_714],
    4 => [10_187, 10_189, 12_793, 14_674, 15_057, 15_071, 13_120, 10_110, 8297, 12_791, 6660, 13_022],
    5 => [11_839, 10_172, 10_806, 14_304, 10_807, 18_697, 14_311, 10_808, 12_552, 1607],
    8 => [17_715, 10_172, 14_141, 11_662, 14_132, 18_697, 12_546, 11_634, 14_134, 19_567],
    7 => [22_223, 11_722, 10_845, 11_703, 14_928, 12_555, 14_974, 10_165, 11_677, 1721, 1203],
    9 => [17_715, 10_172, 14_141, 11_662, 14_132, 18_697, 12_546, 11_634, 14_134, 19_567],
    11 => [10_187, 10_189, 12_793, 14_674, 15_057, 15_071, 13_120, 10_110, 8297, 12_791, 13_022]
  }
  @debug_reagents %{
    3 => [{11_285, 200}, {8952, 20}],
    4 => [{5140, 20}],
    5 => [{17_056, 20}],
    8 => [{17_056, 20}, {17_031, 20}, {17_032, 20}],
    7 => [{5175, 1}, {5176, 1}, {5177, 1}, {5178, 1}, {17_030, 20}, {17_058, 20}],
    9 => [{6265, 5}, {5565, 20}],
    11 => [{17_034, 20}, {17_035, 20}, {17_036, 20}, {17_037, 20}, {17_038, 20}]
  }

  def run do
    seed_account_and_characters()
    seed_extra_accounts()
    seed_mobs()
    seed_game_objects()
    Logger.info("Debug seed ready: #{@account}/#{@account} on Programmer Isle (.go xyz 16303.2 16318.1 69.44 451)")
  end

  defp seed_extra_accounts do
    for {account, character} <- [
          {"debugbuyer", {"Debugbuyer", @human, 1}},
          {"debugbidder", {"Debugbidder", @human, 8}},
          {"debugrival", {"Debugrival", @orc, 1}}
        ] do
      ThistleTea.Account.register(account, account)
      {:ok, %ThistleTea.Account{id: account_id}} = ThistleTea.Account.get_user(account)
      create_character(character, account_id)
    end
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
    |> set_debug_action_bars()
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
      |> set_debug_ammo(class)
      |> set_debug_pet(class)
      |> Character.restore_health_and_mana()

    {:ok, CharacterStore.put(character)}
  end

  defp equip_debug_gear(result), do: result

  defp set_debug_ammo(%Character{player: player} = character, 3), do: %{character | player: %{player | ammo_id: 11_285}}

  defp set_debug_ammo(character, _class), do: character

  defp set_debug_pet(%Character{} = character, 3) do
    level = @level - 1
    xp = PetLevelLoader.levels()[level].next_level_xp - 500

    character
    |> Companion.suspend_as(:hunter_pet, 2960, 1515)
    |> Companion.capture_progress(%PetProgress{level: level, xp: xp, spells: [14_919, 17_260, 24_603]})
  end

  defp set_debug_pet(character, _class), do: character

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
    new_ids = ClassSpell.trainable_spell_ids(unit.class, unit.level) ++ debug_training_spells(unit.class)
    superseded_by = SpellLoader.superseded_by_map(existing ++ new_ids)
    {all_ids, _events} = SpellBook.learn(existing, new_ids, superseded_by)

    %{character | internal: %{internal | spells: all_ids}}
  end

  defp debug_training_spells(3), do: [264 | @pet_training_spells]
  defp debug_training_spells(_class), do: []

  defp set_debug_action_bars(
         %Character{internal: internal, player: %Player{} = player, unit: %{class: class}} = character
       ) do
    learned_spells =
      DBC.all(
        from(s in Spell,
          where: s.id in ^internal.spells,
          select: %{
            id: s.id,
            name: s.name_en_gb,
            level: s.spell_level,
            base_level: s.base_level
          }
        )
      )

    %{
      character
      | player: %{player | action_bars: ActionBars.visible_toggles()},
        internal: %{internal | action_buttons: ActionBars.build(class, learned_spells)}
    }
  end

  defp max_skills(%Character{unit: unit, player: player, internal: internal} = character) do
    derived = SkillLoader.initial_skills(internal.spells, unit.race, unit.class, unit.level)

    skills =
      (player.skills || %{})
      |> Skills.merge(derived)
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
        internal: %{internal | world: WorldRef.open(@map), area: area}
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

    {dx, dy} = @devilsaur_offset
    spawn_mob(@devilsaur_entry, @base_low_guid + 200, {x + dx, y + dy, z}, nil, @hostile_respawn_secs)

    {dx, dy} = @pickpocket_offset
    spawn_mob(@pickpocket_entry, @base_low_guid + 300, {x + dx, y + dy, z}, nil, @hostile_respawn_secs)

    spawn_mob(113, @base_low_guid + 400, {x + 15.0, y - 10.0, z}, nil, 180)
    spawn_mob(54, @base_low_guid + 500, {x + 4.0, y + 2.0, z}, nil, @respawn_secs)
    spawn_mob(6491, @base_low_guid + 600, {x + 4.0, y - 2.0, z}, nil, @respawn_secs)
    spawn_mob(11_069, @base_low_guid + 700, {x - 3.0, y + 2.0, z}, nil, @respawn_secs)
    spawn_mob(2960, @base_low_guid + 800, {x - 10.0, y - 10.0, z}, nil, 180)
    spawn_mob(1766, @base_low_guid + 900, {x - 20.0, y - 10.0, z}, nil, 180)
    spawn_mob(10_090, @base_low_guid + 1000, {x + 2.0, y - 3.0, z}, nil, @respawn_secs)
    spawn_mob(5515, @base_low_guid + 1100, {x - 2.0, y - 3.0, z}, nil, @respawn_secs)
    spawn_mob(9499, @base_low_guid + 1200, {x + 8.0, y - 4.0, z}, nil, @respawn_secs)
    spawn_mob(9499, @base_low_guid + 1201, {x + 14.0, y - 4.0, z}, nil, @respawn_secs)
    spawn_mob(3639, @base_low_guid + 1300, {x + 20.0, y + 36.0, z}, nil, @respawn_secs)
    spawn_mob(5357, @base_low_guid + 1400, {x + 40.0, y - 40.0, z}, nil, @hostile_respawn_secs)
    spawn_mob(1412, @base_low_guid + 1500, {x + 10.0, y + 10.0, z}, %{items: [{14_113, 1}], gold: 0}, 180)
    spawn_mob(9860, @base_low_guid + 1800, {x - 100.0, y, z}, nil, @hostile_respawn_secs)

    for index <- 0..2 do
      spawn_mob(
        @hostile_entry,
        @base_low_guid + 1600 + index,
        {x - 110.0 + index * 8.0, y + 40.0, z},
        nil,
        @hostile_respawn_secs
      )
    end

    [{-2.0, -2.0}, {0.0, -2.0}, {2.0, -2.0}, {-2.0, 2.0}, {0.0, 2.0}, {2.0, 2.0}]
    |> Enum.with_index()
    |> Enum.each(fn {{dx, dy}, index} ->
      spawn_mob(2960, @base_low_guid + 1700 + index, {x - 150.0 + dx, y - 20.0 + dy, z}, nil, @hostile_respawn_secs)
    end)

    spawn_mob(6139, @base_low_guid + 1900, {x + 90.0, y + 50.0, z}, nil, 30, altitude: 18.0, wander: 10.0)
    spawn_mob(11_368, @base_low_guid + 1901, {x + 90.0, y + 10.0, z}, nil, 30, altitude: 18.0)

    for {offset, index} <- [{160.0, 0}, {184.0, 1}] do
      spawn_mob(14_718, @base_low_guid + 2000 + index, {x + offset, y, z}, nil, 30, ai_events: [:hp])
    end

    spawn_mob(599, @base_low_guid + 2100, {x + 160.0, y + 80.0, z}, nil, 30)
    spawn_mob(707, @base_low_guid + 2200, {x + 160.0, y + 150.0, z}, nil, 30)
    spawn_mob(724, @base_low_guid + 2201, {x + 176.0, y + 150.0, z}, nil, 30, wander: 2.0)
    spawn_mob(1729, @base_low_guid + 2300, {x + 90.0, y - 60.0, z}, nil, 30)
    spawn_mob(68, @base_low_guid + 2400, {x - 180.0, y - 100.0, z}, nil, 30)

    spawn_mob(
      @hostile_entry,
      @base_low_guid + 2401,
      {x - 135.0, y - 100.0, z},
      %{items: [{118, 1}], gold: 17},
      30
    )
  end

  defp seed_game_objects do
    {x, y, z} = @spawn_point

    for {entry, dx, dy} <- [
          {138_493, 20.0, 15.0},
          {17_156, 20.0, 22.0},
          {178_965, 25.0, 22.0},
          {176_557, 25.0, 15.0},
          {180_449, 30.0, 15.0},
          {180_450, 30.0, 15.0},
          {37, 20.0, 30.0},
          {17_188, 25.0, 30.0},
          {17_189, 30.0, 30.0},
          {181_598, 40.0, 42.0},
          {164_882, 35.0, 42.0}
        ] do
      template = GameObjectTemplateLoader.cached(entry)
      {ox, oy, oz} = Pathfinding.snap_to_ground(@map, {x + dx, y + dy, z})
      template |> GameObject.build_summoned(WorldRef.open(@map), {ox, oy, oz, 0.0}) |> World.start_entity()
    end
  end

  defp spawn_mob(entry, low_guid, {x, y, z}, loot_override, respawn_secs, opts \\ []) do
    {x, y, z} = Pathfinding.snap_to_ground(@map, {x, y, z})
    z = z + Keyword.get(opts, :altitude, 0.0)
    wander = Keyword.get(opts, :wander, 0.0)

    case Mangos.Repo.one(from(c in Mangos.Creature, where: c.id == ^entry, limit: 1, preload: [:creature_template])) do
      %Mangos.Creature{} = creature ->
        creature = %{
          creature
          | guid: low_guid,
            id2: 0,
            id3: 0,
            id4: 0,
            id5: 0,
            map: @map,
            position_x: x,
            position_y: y,
            position_z: z,
            orientation: 0.0,
            spawntimesecs: respawn_secs,
            spawntimesecsmin: respawn_secs,
            spawntimesecsmax: respawn_secs,
            spawndist: wander,
            movement_type: if(wander > 0, do: 1, else: 0)
        }

        mob =
          creature
          |> MobLoader.load_creature()
          |> Mob.build()
          |> select_ai_events(Keyword.get(opts, :ai_events))

        mob = %{mob | internal: %{mob.internal | loot: %{mob.internal.loot | override: loot_override}}}
        MobLoader.start_mob(mob)

      _ ->
        Logger.warning("Debug seed: creature #{entry} has no spawn row, skipping")
    end
  end

  defp select_ai_events(mob, nil), do: mob

  defp select_ai_events(%Mob{internal: %{creature: creature}} = mob, types) do
    events = Enum.filter(creature.ai_events, &(&1.event_type in types))
    %{mob | internal: %{mob.internal | creature: %{creature | ai_events: events}}}
  end
end
