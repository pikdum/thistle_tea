defmodule ThistleTea.Game.Network.Message.CmsgActivatetaxi do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ACTIVATETAXI

  alias ThistleTea.Game.Player.Taxi

  defstruct [:guid, :source_node, :destination_node]

  @impl ClientMessage
  def handle(
        %__MODULE__{guid: guid, source_node: source, destination_node: destination},
        %{ready: true, character: %Character{}} = state
      ) do
    Taxi.activate(state, guid, [source, destination])
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), source_node::little-size(32), destination_node::little-size(32)>>) do
    %__MODULE__{guid: guid, source_node: source_node, destination_node: destination_node}
  end
end
