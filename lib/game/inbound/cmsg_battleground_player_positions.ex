defmodule ThistleTea.Game.Inbound.CmsgBattlegroundPlayerPositions do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_BATTLEGROUND_PLAYER_POSITIONS

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.positions(state)
end
