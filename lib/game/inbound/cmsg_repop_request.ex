defmodule ThistleTea.Game.Inbound.CmsgRepopRequest do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_REPOP_REQUEST

  alias ThistleTea.Game.World.Entity.Player.Corpses

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Corpses.release(state)
end
