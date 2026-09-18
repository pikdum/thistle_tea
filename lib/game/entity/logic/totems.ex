defmodule ThistleTea.Game.Entity.Logic.Totems do
  @moduledoc """
  Owns player totem slots and releases summons when their owner dies or leaves
  the world. Late summon results cannot attach to a dead owner.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects

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
end
