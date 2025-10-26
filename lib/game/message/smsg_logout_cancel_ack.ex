defmodule ThistleTea.Game.Message.SmsgLogoutCancelAck do
  use ThistleTea.Game.ServerMessage, :SMSG_LOGOUT_CANCEL_ACK

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
