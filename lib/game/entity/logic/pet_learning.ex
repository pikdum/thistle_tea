defmodule ThistleTea.Game.Entity.Logic.PetLearning do
  @moduledoc """
  Requests recipe discovery when a living hunter pet launches a known ability.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  def used(
        %Mob{
          internal: %{pet: %Pet{kind: :hunter, owner_guid: owner, broken?: false, possessed?: false}},
          unit: %{health: health}
        } = pet,
        %Spell{} = spell
      )
      when is_integer(owner) and owner > 0 and is_number(health) and health > 0 do
    if Map.has_key?(pet.internal.spellbook || %{}, spell.id) and not Spell.attribute?(spell, :passive) do
      Effects.enqueue(pet, %Effects.PetAbilityUsed{spell_id: spell.id})
    else
      pet
    end
  end

  def used(entity, _spell), do: entity
end
