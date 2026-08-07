defmodule ThistleTea.Game.Network.Message.CmsgGossipHello do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_HELLO

  alias ThistleTea.Game.Player.Gossip

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Gossip.hello(state, guid)

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end
end
