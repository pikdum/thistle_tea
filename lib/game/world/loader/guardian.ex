defmodule ThistleTea.Game.World.Loader.Guardian do
  @moduledoc """
  Builds autonomous guardians from cached templates and class-level statistics.
  Engineering trinkets scale their creatures from the owner's current skill.
  """

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Guardian
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackPower
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Summon

  def build(owner, %Effects.SummonGuardians{} = effect, position, now, index \\ 0) do
    template = Summon.prototype(effect.entry).creature_template
    default_level = Enum.random(template.min_level..template.max_level)
    level = level(owner, effect, default_level)

    mob =
      Summon.build(effect.entry, owner.internal.world, position, level: level, run?: true, apply_addon_auras?: false)

    guid = Guid.from_low_guid(:pet, effect.entry, Guid.low_guid(mob.object.guid))

    unit = %{
      mob.unit
      | created_by_spell: effect.spell_id,
        faction_template: owner.unit.faction_template,
        pet_number: 0,
        pet_name_timestamp: 0,
        pet_experience: 0,
        pet_next_level_exp: 1000,
        attack_power_model: :summoned_pet,
        base_attack_power: AttackPower.pet_base(mob.unit),
        base_ranged_attack_power: 0
    }

    pet = %Pet{
      owner_guid: owner.object.guid,
      kind: :guardian,
      profile: :combat,
      reaction_state: :aggressive,
      follow_angle: follow_angle(owner, index),
      autocast: MapSet.new(mob.internal.creature.spells || [], & &1.spell_id)
    }

    guardian = %Guardian{expires_at: if(effect.duration_ms > 0, do: now + effect.duration_ms)}

    internal = %{mob.internal | pet: pet, guardian: guardian, loot: nil}
    mob = %{mob | object: %{mob.object | guid: guid}, unit: Stats.recompute(unit), internal: internal}
    mob = Summon.attach_owner(mob, owner.object.guid)
    flags = ((mob.unit.flags || 0) &&& bnot(0x1008)) ||| ((owner.unit.flags || 0) &&& 0x1008)
    mob = %{mob | unit: %{mob.unit | flags: flags}}

    Mob.apply_addon_auras(mob, now)
  end

  defp level(%Character{} = owner, effect, default) do
    case ItemStore.get(effect.cast_item_guid) do
      %Item{internal: %{template: %ItemTemplate{required_skill: 202, inventory_type: 12}}} ->
        {temporary, permanent} = Map.get(Skills.bonuses(owner), 202, {0, 0})
        skill = Skills.value(owner.player.skills, 202) + temporary + permanent
        if skill > 0, do: max(div(skill, 5), 1), else: default

      _ ->
        default
    end
  end

  defp level(%{unit: %{level: level}}, %Effects.SummonGuardians{level_offset: offset}, default) when offset <= 0 do
    result = trunc(level + offset)
    if result in 1..63, do: result, else: default
  end

  defp level(_owner, _effect, default), do: default

  defp follow_angle(owner, index) do
    combat_count = if match?(%Character{}, owner) and Companion.active_guid(owner), do: 1, else: 0
    angle = :math.pi() / 2 + :math.pi() / 6 * (map_size(owner.internal.guardians) + combat_count + index)
    :math.fmod(angle, :math.pi() * 2)
  end
end
