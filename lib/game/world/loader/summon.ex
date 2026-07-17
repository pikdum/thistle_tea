defmodule ThistleTea.Game.World.Loader.Summon do
  @moduledoc """
  ETS cache of fully-loaded creature prototypes for script-driven temporary
  summons, keyed by entry: the first summon of an entry runs the normal mob
  loading pipeline against a synthetic spawn row and caches the result, so
  later summons build without touching the database. Summoned mob guids get
  a session-unique low guid offset far above the seed data's spawn guids.
  """
  import Bitwise, only: [&&&: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.DBC.CreatureFamily
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @low_guid_base 0x400000
  @spell_attr_passive 0x40

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def build(entry, world, {x, y, z, o}, opts \\ []) when is_integer(entry) and is_list(opts) do
    creature = template(entry)
    world = WorldRef.coerce(world)

    %{creature | guid: next_low_guid(), map: world.map_id, position_x: x, position_y: y, position_z: z, orientation: o}
    |> Mob.build()
    |> then(&%{&1 | internal: %{&1.internal | world: world}})
    |> Mob.prepare_summon(opts)
  end

  def build_pet(entry, %{
        object: %{guid: owner_guid},
        unit: owner_unit,
        internal: %{world: world},
        movement_block: %{position: position}
      })
      when is_integer(entry) and is_integer(owner_guid) do
    with %Mob{} = mob <- build(entry, world, position),
         level when is_integer(level) <- owner_unit.level do
      guid = Guid.from_low_guid(:pet, entry, next_low_guid())
      spellbook = pet_spellbook(entry, level)
      creature = %{mob.internal.creature | spells: pet_action_spells(spellbook)}
      hunter_pet? = hunter_pet?(creature)
      stats = pet_stats(if(hunter_pet?, do: 1, else: entry), level)

      unit =
        mob.unit
        |> apply_pet_stats(stats, level)
        |> apply_pet_resources(hunter_pet?)
        |> then(fn unit ->
          %{
            unit
            | summon: 0,
              summoned_by: owner_guid,
              created_by: owner_guid,
              faction_template: owner_unit.faction_template,
              pet_number: Guid.low_guid(guid),
              pet_name_timestamp: System.system_time(:second),
              pet_loyalty: 0,
              pet_flags: 0
          }
        end)

      internal = %{
        mob.internal
        | pet: %Pet{
            owner_guid: owner_guid,
            profile: :combat,
            kind: if(hunter_pet?, do: :hunter, else: :summon),
            food_mask: if(hunter_pet?, do: pet_food_mask(creature.family), else: 0)
          },
          spawn: %{mob.internal.spawn | temporary?: true, respawn_delay_ms: nil},
          loot: nil,
          in_combat: false,
          running: true,
          spellbook: spellbook,
          creature: creature
      }

      %{mob | object: %{mob.object | guid: guid}, unit: unit, internal: internal}
    else
      _ -> nil
    end
  end

  def build_pet(_entry, _owner), do: nil

  def possess(%Mob{} = mob, %{object: %{guid: owner_guid}, unit: owner_unit}, spell_id)
      when is_integer(owner_guid) and is_integer(spell_id) do
    original_flags = mob.unit.flags || 0

    pet = %Pet{
      owner_guid: owner_guid,
      profile: :combat,
      kind: :possessed,
      food_mask: 0,
      control_spell_id: spell_id,
      original_faction_template: mob.unit.faction_template,
      original_npc_flags: mob.unit.npc_flags,
      possession_original_unit_flags: original_flags,
      possessed?: true,
      command_state: :stay,
      reaction_state: :passive
    }

    unit = %{
      mob.unit
      | charmed_by: owner_guid,
        summoned_by: owner_guid,
        created_by: owner_guid,
        created_by_spell: spell_id,
        faction_template: owner_unit.faction_template,
        npc_flags: 0,
        flags: Bitwise.bor(original_flags, 0x01000000),
        level: owner_unit.level,
        target: 0
    }

    internal = %{
      mob.internal
      | pet: pet,
        in_combat: false,
        threat: %{},
        running: true
    }

    %{mob | unit: unit, internal: internal}
  end

  def pet_spellbook(entry, level) when is_integer(entry) and is_integer(level) do
    key = {:pet_spellbook, entry, level}

    case :ets.lookup(__MODULE__, key) do
      [{^key, spellbook}] ->
        spellbook

      _ ->
        spellbook = entry |> pet_spell_profile() |> highest_active_spell_ids(level) |> SpellLoader.build_spellbook()
        :ets.insert(__MODULE__, {key, spellbook})
        spellbook
    end
  end

  def pet_spellbook(_entry, _level), do: %{}

  defp pet_spell_profile(entry) do
    case Mangos.Repo.get(Mangos.PetCreateInfoSpell, entry) do
      %Mangos.PetCreateInfoSpell{} = row ->
        spell_ids = Mangos.PetCreateInfoSpell.spell_ids(row)

        skill_lines =
          DBC.all(
            from(ability in SkillLineAbility,
              where: ability.spell in ^spell_ids,
              select: ability.skill_line,
              distinct: true
            )
          )

        {skill_lines, spell_ids ++ grimoire_pet_spell_ids()}

      _ ->
        {[], []}
    end
  end

  defp grimoire_pet_spell_ids do
    key = :grimoire_pet_spell_ids

    case :ets.lookup(__MODULE__, key) do
      [{^key, spell_ids}] ->
        spell_ids

      _ ->
        spell_ids =
          Mangos.Repo.all(
            from(item in Mangos.ItemTemplate,
              where: like(item.name, "Grimoire of %") and item.spellid_1 > 0,
              select: item.spellid_1
            )
          )
          |> SpellLoader.learned_spell_ids()

        :ets.insert(__MODULE__, {key, spell_ids})
        spell_ids
    end
  end

  defp highest_active_spell_ids({[], _spell_ids}, _level), do: []

  defp highest_active_spell_ids({skill_lines, spell_ids}, level) do
    DBC.all(
      from(ability in SkillLineAbility,
        join: spell in Spell,
        on: spell.id == ability.spell,
        where: ability.skill_line in ^skill_lines and ability.spell in ^spell_ids and spell.base_level <= ^level,
        select: %{id: spell.id, name: spell.name_en_gb, level: spell.base_level, attributes: spell.attributes}
      )
    )
    |> Enum.reject(&passive_spell?/1)
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {_name, ranks} -> Enum.max_by(ranks, & &1.level).id end)
    |> Enum.sort()
  end

  defp passive_spell?(%{attributes: attributes}) when is_integer(attributes),
    do: (attributes &&& @spell_attr_passive) != 0

  defp passive_spell?(_spell), do: false

  defp pet_action_spells(spellbook) when is_map(spellbook) do
    spellbook
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn spell ->
      cast_target = if SpellData.harmful?(spell), do: :victim, else: :self
      %CreatureSpell{spell_id: spell.id, cast_target: cast_target}
    end)
  end

  defp template(entry) do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %Mangos.Creature{} = creature}] -> creature
      _ -> load(entry)
    end
  end

  defp load(entry) do
    creature =
      %Mangos.Creature{
        guid: 0,
        id: entry,
        map: 0,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        orientation: 0.0,
        movement_type: 0
      }
      |> MobLoader.load_creature()

    :ets.insert(__MODULE__, {entry, creature})

    creature
  end

  defp pet_stats(entry, level) do
    key = {:pet_stats, entry, level}

    case :ets.lookup(__MODULE__, key) do
      [{^key, stats}] ->
        stats

      _ ->
        stats = Mangos.Repo.get_by(Mangos.PetLevelStats, entry: entry, level: level)
        :ets.insert(__MODULE__, {key, stats})
        stats
    end
  end

  defp next_low_guid do
    @low_guid_base + :erlang.unique_integer([:positive, :monotonic])
  end

  defp hunter_pet?(%{type_flags: type_flags}) when is_integer(type_flags), do: (type_flags &&& 0x1) != 0
  defp hunter_pet?(_creature), do: false

  defp pet_food_mask(family) when is_integer(family) and family > 0 do
    case DBC.get(CreatureFamily, family) do
      %CreatureFamily{pet_food_mask: food_mask} -> food_mask
      _ -> 0
    end
  end

  defp pet_food_mask(_family), do: 0

  defp apply_pet_stats(unit, %Mangos.PetLevelStats{} = stats, level) do
    %{
      unit
      | level: level,
        health: stats.health,
        max_health: stats.health,
        power1: stats.mana,
        max_power1: stats.mana,
        normal_resistance: stats.armor,
        base_normal_resistance: stats.armor,
        min_damage: stats.dmg_min,
        max_damage: stats.dmg_max,
        base_min_damage: stats.dmg_min,
        base_max_damage: stats.dmg_max,
        strength: stats.strength,
        agility: stats.agility,
        stamina: stats.stamina,
        intellect: stats.intellect,
        spirit: stats.spirit
    }
  end

  defp apply_pet_stats(unit, _stats, level), do: %{unit | level: level}

  defp apply_pet_resources(unit, true) do
    %{unit | power_type: 2, power3: 100, max_power3: 100, power5: 166_500, max_power5: 1_050_000}
  end

  defp apply_pet_resources(unit, false), do: unit
end
