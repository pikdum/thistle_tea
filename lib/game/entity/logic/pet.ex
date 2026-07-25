defmodule ThistleTea.Game.Entity.Logic.Pet do
  @moduledoc """
  Pure transitions for character-owned pet state.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects

  def dismiss(entity, reason \\ nil)

  def dismiss(%Character{unit: %Unit{summon: pet_guid} = unit, internal: %Internal{} = internal} = character, reason)
      when is_integer(pet_guid) and pet_guid > 0 do
    internal =
      if reason == :owner_died do
        internal
      else
        %{internal | active_pet_entry: nil, active_pet_spell_id: nil}
      end

    character = %{character | unit: %{unit | summon: 0}, internal: internal}
    {character, [Effects.dismiss_pet(pet_guid)]}
  end

  def dismiss(entity, _reason), do: {entity, []}
end
