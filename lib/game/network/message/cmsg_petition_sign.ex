defmodule ThistleTea.Game.Network.Message.CmsgPetitionSign do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SIGN

  defstruct [:item_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _unknown::8, _rest::binary>>), do: %__MODULE__{item_guid: guid}
end
