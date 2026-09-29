defmodule ThistleTea.Game.Network.Message.CmsgPetitionSign do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SIGN

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:item_guid]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid}, state), do: Petitions.sign(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _unknown::8, _rest::binary>>), do: %__MODULE__{item_guid: guid}
end
