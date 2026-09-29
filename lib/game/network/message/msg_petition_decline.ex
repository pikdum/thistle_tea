defmodule ThistleTea.Game.Network.Message.MsgPetitionDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_PETITION_DECLINE

  defstruct [:signer_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{signer_guid: guid}), do: <<guid::little-size(64)>>
end
