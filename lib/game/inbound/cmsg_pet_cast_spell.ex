defmodule ThistleTea.Game.Inbound.CmsgPetCastSpell do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PET_CAST_SPELL

  alias ThistleTea.Game.World.Entity.Player.PetActions

  defstruct [:pet_guid, :spell_id, :spell_cast_targets]

  @impl ClientMessage
  def from_binary(<<pet_guid::little-size(64), spell_id::little-size(32), targets::binary>>) do
    %__MODULE__{pet_guid: pet_guid, spell_id: spell_id, spell_cast_targets: targets}
  end

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: pet_guid, spell_id: spell_id, spell_cast_targets: targets}, state),
    do: PetActions.cast(state, pet_guid, spell_id, targets)
end
