defmodule ThistleTea.Game.Network.Message.CmsgTurnInPetition do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TURN_IN_PETITION

  defstruct [:item_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end
