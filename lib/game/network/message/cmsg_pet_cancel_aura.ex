defmodule ThistleTea.Game.Network.Message.CmsgPetCancelAura do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_CANCEL_AURA

  alias ThistleTea.Game.Player.PetActions

  defstruct [:pet_guid, :spell_id]

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid, spell_id: spell}, state), do: PetActions.cancel_aura(state, guid, spell)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), spell::little-size(32)>>), do: %__MODULE__{pet_guid: guid, spell_id: spell}
end
