defmodule ThistleTea.Game.Network.Message.CmsgBattlegroundPlayerPositions do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_BATTLEGROUND_PLAYER_POSITIONS

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.positions(state)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
