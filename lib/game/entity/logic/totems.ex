defmodule ThistleTea.Game.Entity.Logic.Totems do
  @moduledoc """
  Builds owned totems and tracks elemental slots separately from independent
  wards. Player death releases summons; creature wards can outlive their caster.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  @regeneration_effects [:heal, :heal_max_health, :heal_mechanical, :energize]
  @regeneration_auras [:periodic_heal, :periodic_energize, :obs_mod_health, :obs_mod_mana, :mod_regen, :mod_power_regen]

  def immune_effect?(%{object: %{guid: guid}}, %CastContext{caster_guid: guid}, _spell, _effect), do: false

  def immune_effect?(%{internal: %Internal{totem: %Totem{}}}, _context, %Spell{} = spell, %Effect{} = effect) do
    not Spell.family_flag?(spell, 11, 0x04006000, 0) and
      (effect.type in [:attack_me | @regeneration_effects] or
         (effect.type in [:apply_aura, :apply_area_aura] and
            (Spell.harmful?(spell) or effect.aura in @regeneration_auras)))
  end

  def immune_effect?(_entity, _context, _spell, _effect), do: false

  def prepare(%Mob{} = mob, owner, %Effects.SummonTotem{} = effect, now) do
    unit = %{
      mob.unit
      | faction_template: owner.unit.faction_template,
        level: owner.unit.level,
        created_by_spell: effect.spell_id,
        created_by: owner.object.guid,
        summoned_by: owner.object.guid,
        stat_model: :creature,
        flags: Bitwise.bor(mob.unit.flags || 0, Bitwise.band(owner.unit.flags || 0, 0x1000))
    }

    unit = if effect.health > 0, do: %{unit | base_health: effect.health}, else: unit
    unit = Stats.recompute(unit)
    unit = %{unit | health: unit.max_health}

    totem = %Totem{
      owner_guid: owner.object.guid,
      expires_at: now + effect.duration_ms,
      owner_spell_modifiers: Modifiers.holders(owner)
    }

    internal = %{mob.internal | totem: totem, rooted?: true, loot: nil}
    %{mob | unit: unit, internal: internal}
  end

  def position({x, y, z, orientation}, slot) do
    offset = if slot in 1..4, do: :math.pi() / 4 - (slot - 1) * :math.pi() / 2, else: 0.0
    angle = orientation + offset
    {x + 2.0 * :math.cos(angle), y + 2.0 * :math.sin(angle), z, orientation}
  end

  def started(%{internal: %Internal{} = internal} = entity, slot, guid) do
    if Death.alive?(entity) or is_struct(entity, Mob) do
      key = slot || {:unslotted, guid}
      %{entity | internal: %{internal | totem_guids: Map.put(internal.totem_guids, key, guid)}}
    else
      Effects.enqueue(entity, Effects.despawn_entity(guid))
    end
  end

  def dismiss_all(%Character{internal: %Internal{} = internal} = character) do
    effects =
      internal.totem_guids
      |> Map.values()
      |> Enum.uniq()
      |> Enum.map(&Effects.despawn_entity/1)

    %{character | internal: %{internal | totem_guids: %{}}}
    |> Effects.enqueue(effects)
  end

  def dismiss_all(entity), do: entity

  def stopped(%{internal: %Internal{} = internal} = character, guid) do
    totems = Map.reject(internal.totem_guids, fn {_slot, current} -> current == guid end)
    %{character | internal: %{internal | totem_guids: totems}}
  end
end
