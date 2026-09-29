defmodule ThistleTea.Game.Network.Message.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
