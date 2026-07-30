defmodule ThistleTea.Game.Network.Message.SmsgShowtaxinodes do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SHOWTAXINODES

  defstruct [:guid, :nearest_node, nodes: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, nearest_node: nearest_node, nodes: nodes}) do
    <<1::little-size(32), guid::little-size(64), nearest_node::little-size(32)>> <>
      Enum.reduce(nodes, <<>>, &(&2 <> <<&1::little-size(32)>>))
  end
end
