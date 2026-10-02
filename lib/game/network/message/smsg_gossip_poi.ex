defmodule ThistleTea.Game.Network.Message.SmsgGossipPoi do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GOSSIP_POI

  defstruct [:flags, :x, :y, :icon, :data, :name]

  @impl ServerMessage
  def to_binary(%__MODULE__{flags: flags, x: x, y: y, icon: icon, data: data, name: name}) do
    <<flags::little-size(32), x::little-float-size(32), y::little-float-size(32), icon::little-size(32),
      data::little-size(32), name::binary, 0>>
  end
end
