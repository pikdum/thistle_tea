defmodule ThistleTea.Game.Inbound.CmsgActivatetaxi do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ACTIVATETAXI

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Taxi

  defstruct [:guid, :source_node, :destination_node]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), source_node::little-size(32), destination_node::little-size(32)>>) do
    %__MODULE__{guid: guid, source_node: source_node, destination_node: destination_node}
  end

  @impl ClientMessage
  def handle(
        %__MODULE__{guid: guid, source_node: source, destination_node: destination},
        %{ready: true, character: %Character{}} = state
      ) do
    Taxi.activate(state, guid, [source, destination])
  end

  def handle(%__MODULE__{}, state), do: state
end
