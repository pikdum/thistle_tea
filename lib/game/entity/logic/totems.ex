defmodule ThistleTea.Game.Entity.Logic.Totems do
  @moduledoc """
  Owns player totem slots and releases summons when their owner dies or leaves
  the world. Late summon results cannot attach to a dead owner.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

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

  def started(%Character{internal: %Internal{} = internal} = character, slot, guid) do
    if Death.alive?(character) do
      %{character | internal: %{internal | totem_guids: Map.put(internal.totem_guids, slot, guid)}}
    else
      Effects.enqueue(character, Effects.despawn_entity(guid))
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

  def stopped(%Character{internal: %Internal{} = internal} = character, guid) do
    totems = Map.reject(internal.totem_guids, fn {_slot, current} -> current == guid end)
    %{character | internal: %{internal | totem_guids: totems}}
  end
end
