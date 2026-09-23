defmodule ThistleTea.Game.Network.Message.CmsgPetAbandon do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_ABANDON

  alias ThistleTea.Game.Player.Pets

  defstruct [:pet_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{pet_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid}, state), do: Pets.abandon(state, guid)
end
