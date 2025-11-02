defmodule ThistleTea.Game.Network.Message.SmsgChatPlayerNotFound do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CHAT_PLAYER_NOT_FOUND

  defstruct [:name]

  @impl ServerMessage
  def to_binary(%__MODULE__{name: name}) do
    <<name::binary, 0>>
  end
end
