defmodule ThistleTea.Game.Inbound.MsgMinimapPing do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_MINIMAP_PING

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:x, :y]

  @impl ClientMessage
  def from_binary(payload) do
    <<x::little-float-size(32), y::little-float-size(32)>> = payload
    %__MODULE__{x: x, y: y}
  end

  @impl ClientMessage
  def handle(%__MODULE__{x: x, y: y}, state), do: Groups.minimap_ping(state, x, y)
end
