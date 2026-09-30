defmodule ThistleTea.Game.Inbound.CmsgBattlefieldStatus do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BATTLEFIELD_STATUS

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.send_status(state)
end
