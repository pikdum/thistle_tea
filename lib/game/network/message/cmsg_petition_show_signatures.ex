defmodule ThistleTea.Game.Network.Message.CmsgPetitionShowSignatures do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SHOW_SIGNATURES

  defstruct [:item_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{item_guid: guid}
end
