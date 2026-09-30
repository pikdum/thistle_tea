defmodule ThistleTea.Game.Inbound.CmsgPetCancelAura do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PET_CANCEL_AURA

  alias ThistleTea.Game.World.Entity.Player.PetActions

  defstruct [:pet_guid, :spell_id]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), spell::little-size(32)>>), do: %__MODULE__{pet_guid: guid, spell_id: spell}

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid, spell_id: spell}, state), do: PetActions.cancel_aura(state, guid, spell)
end
