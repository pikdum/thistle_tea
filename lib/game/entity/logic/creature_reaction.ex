defmodule ThistleTea.Game.Entity.Logic.CreatureReaction do
  @moduledoc "Creature reaction modes shared by proximity acquisition, combat entry, and scripted changes."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects

  @passive_extra_flags 0x00000080 + 0x00020000
  @no_aggro 0x00000002
  @ignore_combat 0x02000000

  def mode(%Mob{internal: %{pet: %Pet{reaction_state: reaction}}}), do: reaction

  def mode(%Mob{internal: %{creature: %Creature{reaction_state: reaction}}})
      when reaction in [:passive, :defensive, :aggressive], do: reaction

  def mode(%Mob{internal: %{totem: totem}}) when not is_nil(totem), do: :passive

  def mode(%Mob{internal: %{creature: %Creature{} = creature}}) do
    cond do
      ((creature.extra_flags || 0) &&& @passive_extra_flags) != 0 -> :passive
      ((creature.static_flags || 0) &&& @ignore_combat) != 0 -> :passive
      ((creature.extra_flags || 0) &&& @no_aggro) != 0 -> :defensive
      true -> :aggressive
    end
  end

  def mode(%Mob{}), do: :aggressive

  def set(%Mob{internal: %{pet: %Pet{} = pet}} = entity, reaction)
      when reaction in [:passive, :defensive, :aggressive] do
    if pet.reaction_state == reaction do
      entity
    else
      entity = %{
        entity
        | internal: %{entity.internal | pet: %{pet | reaction_state: reaction}, broadcast_update?: true}
      }

      Effects.enqueue(entity, %Effects.PetReactionChanged{
        source_guid: entity.object.guid,
        target_guid: pet.owner_guid,
        reaction_state: reaction
      })
    end
  end

  def set(%Mob{} = entity, reaction) when reaction in [:passive, :defensive, :aggressive] do
    creature = entity.internal.creature || %Creature{}
    %{entity | internal: %{entity.internal | creature: %{creature | reaction_state: reaction}, broadcast_update?: true}}
  end
end
