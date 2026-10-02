defmodule ThistleTea.Game.Inbound.CmsgGmticketSystemstatus do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMTICKET_SYSTEMSTATUS, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Tickets

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Tickets.system_status(state)
end
