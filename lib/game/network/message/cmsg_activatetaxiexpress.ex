defmodule ThistleTea.Game.Network.Message.CmsgActivatetaxiexpress do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ACTIVATETAXIEXPRESS

  alias ThistleTea.Game.Player.Taxi

  defstruct [:guid, :total_cost, nodes: []]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, nodes: nodes}, %{ready: true, character: %Character{}} = state) do
    Taxi.activate(state, guid, nodes)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), total_cost::little-size(32), node_count::little-size(32), rest::binary>>) do
    <<nodes_binary::binary-size(^node_count * 4)>> = rest

    nodes = for <<node::little-size(32) <- nodes_binary>>, do: node
    %__MODULE__{guid: guid, total_cost: total_cost, nodes: nodes}
  end
end
