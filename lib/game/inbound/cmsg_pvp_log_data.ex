defmodule ThistleTea.Game.Inbound.CmsgPvpLogData do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_PVP_LOG_DATA

  alias ThistleTea.Game.World.Entity.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.scoreboard(state)
end
