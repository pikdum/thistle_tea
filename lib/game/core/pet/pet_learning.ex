defmodule ThistleTea.Game.Core.Pet.PetLearning do
  @moduledoc """
  Requests recipe discovery when a living hunter pet launches a known ability.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell

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
