defmodule ThistleTea.Game.Network.Message.MsgMinimapPingResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_MINIMAP_PING

  defstruct [:guid, :x, :y]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, x: x, y: y}) do
    <<guid::little-size(64), x::little-float-size(32), y::little-float-size(32)>>
  end
end
