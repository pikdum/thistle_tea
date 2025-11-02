defmodule ThistleTea.Game.Network.Message.SmsgLogoutCancelAck do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOGOUT_CANCEL_ACK

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
