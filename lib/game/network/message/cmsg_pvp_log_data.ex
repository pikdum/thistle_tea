defmodule ThistleTea.Game.Network.Message.CmsgPvpLogData do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PVP_LOG_DATA

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.scoreboard(state)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
