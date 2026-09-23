defmodule ThistleTea.Game.Network.Message.MsgCorpseQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_CORPSE_QUERY

  defstruct [:map, :position, :corpse_map]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map, position: {x, y, z}, corpse_map: corpse_map}) do
    <<
      1::little-size(8),
      map::little-signed-size(32),
      x::little-float-size(32),
      y::little-float-size(32),
      z::little-float-size(32),
      corpse_map || map::little-size(32)
    >>
  end

  def to_binary(%__MODULE__{}) do
    <<0::little-size(8)>>
  end
end
