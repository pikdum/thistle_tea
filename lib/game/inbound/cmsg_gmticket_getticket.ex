defmodule ThistleTea.Game.Inbound.CmsgGmticketGetticket do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMTICKET_GETTICKET, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Tickets

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Tickets.show(state)
end
