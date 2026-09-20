defmodule ThistleTea.Game.Network.Message.CmsgPetUnlearn do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_UNLEARN

  alias ThistleTea.Game.Player.PetUntraining

  defstruct [:pet_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{pet_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid}, state), do: PetUntraining.complete(state, guid)
end
