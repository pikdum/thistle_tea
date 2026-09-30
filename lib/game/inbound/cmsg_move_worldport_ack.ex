defmodule ThistleTea.Game.Inbound.CmsgMoveWorldportAck do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_MOVE_WORLDPORT_ACK

  alias ThistleTea.Game.World.Entity.Player.Travel

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Travel.worldport_ack(state)
end
