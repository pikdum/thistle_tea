defmodule ThistleTea.Game.Inbound.CmsgGossipHello do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GOSSIP_HELLO

  alias ThistleTea.Game.World.Entity.Player.Gossip

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Gossip.hello(state, guid)
end
