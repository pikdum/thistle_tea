defmodule ThistleTea.Game.Entity.Logic.MiniPet do
  @moduledoc """
  The player's noncombat pet slot, independent of controlled companions.
  Removal clears the relationship before requesting entity teardown.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Logic.Effects

  def activate(%Character{} = character, %EntityRef{} = ref) do
    %{character | internal: %{character.internal | mini_pet: ref}}
  end

  def active_ref(%Character{} = character), do: character.internal.mini_pet

  def removed(%Character{internal: %{mini_pet: %EntityRef{guid: guid}}} = character, guid) do
    %{character | internal: %{character.internal | mini_pet: nil}}
  end

  def removed(%Character{} = character, _guid), do: character

  def dismiss(%Character{internal: %{mini_pet: %EntityRef{guid: guid}}} = character) do
    character
    |> removed(guid)
    |> Effects.enqueue(%Effects.DespawnEntity{target_guid: guid})
  end

  def dismiss(entity), do: entity
end
