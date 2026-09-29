defmodule ThistleTea.Game.Network.Message.MsgMinimapPing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MINIMAP_PING

  defstruct [:x, :y]

  @impl ClientMessage
  def from_binary(payload) do
    <<x::little-float-size(32), y::little-float-size(32)>> = payload
    %__MODULE__{x: x, y: y}
  end
end
