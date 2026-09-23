defmodule ThistleTea.Game.Network.Message.CmsgPetAction do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_ACTION

  import Bitwise, only: [&&&: 2, >>>: 2]

  alias ThistleTea.Game.Player.PetActions

  defstruct [:pet_guid, :action, :action_type, :target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: PetActions.handle(message, state)

  @impl ClientMessage
  def from_binary(<<pet_guid::little-size(64), data::little-size(32), target_guid::little-size(64)>>) do
    %__MODULE__{pet_guid: pet_guid, action: data &&& 0x00FFFFFF, action_type: data >>> 24, target_guid: target_guid}
  end
end
