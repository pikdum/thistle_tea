defmodule ThistleTea.Game.Inbound.CmsgAttackstop do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ATTACKSTOP

  alias ThistleTea.Game.World.Entity.Player.Attacking

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Attacking.stop(state)
end
