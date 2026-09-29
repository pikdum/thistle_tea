defmodule ThistleTea.Game.Network.Message.CmsgBattlegroundPlayerPositions do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_BATTLEGROUND_PLAYER_POSITIONS

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
