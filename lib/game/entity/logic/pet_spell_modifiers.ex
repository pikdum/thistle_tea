defmodule ThistleTea.Game.Entity.Logic.PetSpellModifiers do
  @moduledoc """
  Projects an owner's spell modifiers into its pet and refreshes affected
  permanent self-cast passives through normal aura transitions.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers

  def sync(%Mob{internal: %{pet: %Pet{owner_guid: owner} = control}} = pet, owner, holders, now) do
    updated = %{pet | internal: %{pet.internal | pet: %{control | owner_spell_modifiers: holders}}}

    pet.unit.auras
    |> List.wrap()
    |> Enum.filter(&refresh?(&1, pet, updated))
    |> Enum.reduce(updated, &apply_passive(&2, &1.spell, now))
  end

  def sync(pet, _owner, _holders, _now), do: pet

  def apply_passive(%Mob{} = pet, %Spell{} = spell, now) do
    context = %CastContext{
      caster_guid: pet.object.guid,
      caster_owner_guid: pet.internal.pet.owner_guid,
      caster_level: pet.unit.level,
      target_guid: pet.object.guid,
      spell: spell,
      spell_modifiers: Modifiers.snapshot(pet, spell)
    }

    {pet, events} = Aura.apply_spell(pet, context, spell, now)
    Effects.enqueue(pet, events)
  end

  defp refresh?(%Holder{caster_guid: caster, expires_at: expires, spell: spell}, pet, updated)
       when expires in [nil, -1] do
    caster == pet.object.guid and Spell.attribute?(spell, :passive) and
      Modifiers.snapshot(pet, spell) != Modifiers.snapshot(updated, spell)
  end

  defp refresh?(_holder, _pet, _updated), do: false
end
