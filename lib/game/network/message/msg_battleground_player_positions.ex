defmodule ThistleTea.Game.Network.Message.MsgBattlegroundPlayerPositions do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_BATTLEGROUND_PLAYER_POSITIONS

  defstruct teammates: [], carriers: []

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<length(message.teammates)::little-size(32)>> <>
      positions(message.teammates) <>
      <<length(message.carriers)::little-size(8)>> <>
      positions(message.carriers)
  end

  defp positions(entries) do
    Enum.map_join(entries, fn entry ->
      <<entry.guid::little-size(64), entry.x::little-float-size(32), entry.y::little-float-size(32)>>
    end)
  end
end
