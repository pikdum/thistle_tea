defmodule ThistleTea.Game.Inbound.CmsgGmticketDeleteticket do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMTICKET_DELETETICKET, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Tickets

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Tickets.abandon(state)
end
