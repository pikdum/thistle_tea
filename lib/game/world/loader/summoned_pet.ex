defmodule ThistleTea.Game.World.Loader.SummonedPet do
  @moduledoc """
  Builds single-slot summoned combat pets from cached pet and creature level
  data, retaining template spells, owner level, and source lifetime.
  """

  alias ThistleTea.DB.Mangos.PetLevelStats
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Pathfinding

  def build(%Mob{} = owner, %Effects.SummonPet{} = effect) do
    level = max(owner.unit.level + trunc(effect.level_offset), 1)
    {x, y, z, orientation} = owner.movement_block.position
    angle = orientation + :math.pi() / 2
    position = {x + 2.0 * :math.cos(angle), y + 2.0 * :math.sin(angle), z, orientation}
    build_pet(owner, effect, level, position, [])
  end

  def build(owner, %Effects.SummonControlledPet{} = effect) when is_struct(owner, Mob) or is_struct(owner, Character) do
    {x, y, z, orientation} = owner.movement_block.position
    position = controlled_position(owner, effect, {x, y, z, -orientation})
    build_pet(owner, effect, owner.unit.level, position, despawn_delay_ms: effect.duration_ms, fixed_name?: true)
  end

  defp controlled_position(
         owner,
         %Effects.SummonControlledPet{resolve_collision?: true, position: {x, y, z, o}},
         {sx, sy, sz, _o}
       ) do
    {x, y, z} = Pathfinding.first_collision_position(owner.internal.world.map_id, {sx, sy, sz}, {x, y, z})
    {x, y, z, o}
  end

  defp controlled_position(_owner, %Effects.SummonControlledPet{position: position}, fallback), do: position || fallback

  defp build_pet(owner, effect, level, position, opts) do
    entry = effect.entry

    mob =
      Summon.build(entry, owner.internal.world, position,
        level: level,
        run?: true,
        apply_addon_auras?: false,
        stat_model: :creature,
        despawn_delay_ms: Keyword.get(opts, :despawn_delay_ms),
        despawn_type: 3
      )

    guid = Guid.from_low_guid(:pet, entry, Guid.low_guid(mob.object.guid))
    learned = Summon.pet_spellbook(entry, level)
    spellbook = Map.merge(mob.internal.spellbook || %{}, learned)
    spells = Enum.uniq_by((mob.internal.creature.spells || []) ++ PetTraining.action_spells(learned), & &1.spell_id)
    unit = pet_stats(mob.unit, Summon.pet_stats(entry, level))

    unit = %{
      unit
      | created_by_spell: effect.spell_id,
        faction_template: owner.unit.faction_template,
        flags: Bitwise.band(owner.unit.flags || 0, 0x1000),
        npc_flags: 0,
        dynamic_flags: 0,
        pet_number: 0,
        pet_name_timestamp: if(Keyword.get(opts, :fixed_name?, false), do: 0, else: System.system_time(:second)),
        pet_experience: 0,
        pet_next_level_exp: 1000,
        attack_power_model: if(entry == 416, do: :imp, else: :summoned_pet),
        base_attack_power: if(entry == 416, do: unit.base_strength - 10, else: unit.base_strength * 2 - 20),
        base_ranged_attack_power: 0
    }

    unit = Stats.recompute(unit)

    pet = %Pet{
      owner_guid: owner.object.guid,
      kind: if(is_struct(owner, Character), do: :summon, else: :creature_pet),
      profile: :combat,
      reaction_state: if(is_struct(owner, Character), do: :defensive, else: :aggressive),
      autocast: MapSet.new(spells, & &1.spell_id)
    }

    internal = %{
      mob.internal
      | pet: pet,
        loot: nil,
        spellbook: spellbook,
        creature: %{mob.internal.creature | spells: spells}
    }

    %{mob | object: %{mob.object | guid: guid}, unit: unit, internal: internal}
    |> Summon.attach_owner(owner.object.guid)
    |> Summon.apply_pet_passive_auras(entry, level)
    |> PetTraining.restore_passives(Time.now())
    |> Mob.apply_addon_auras(Time.now())
    |> then(&%{&1 | unit: %{&1.unit | health: &1.unit.max_health, power1: &1.unit.max_power1}})
  end

  defp pet_stats(unit, %PetLevelStats{} = stats) do
    %{
      unit
      | base_health: stats.health,
        base_mana: stats.mana,
        base_strength: stats.strength,
        base_agility: stats.agility,
        base_stamina: stats.stamina,
        base_intellect: stats.intellect,
        base_spirit: stats.spirit,
        base_normal_resistance: if(stats.armor > 0, do: stats.armor, else: unit.base_normal_resistance),
        base_min_damage: if(stats.dmg_min > 0 and stats.dmg_max > 0, do: stats.dmg_min, else: unit.base_min_damage),
        base_max_damage: if(stats.dmg_min > 0 and stats.dmg_max > 0, do: stats.dmg_max, else: unit.base_max_damage)
    }
  end

  defp pet_stats(unit, nil), do: unit
end
