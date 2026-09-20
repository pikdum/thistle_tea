defmodule ThistleTea.Game.Network.Message.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.Player.Travel

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Travel.worldport_ack(state)

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
