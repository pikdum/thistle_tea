defmodule ThistleTea.Game.Inbound.CmsgGossipSelectOption do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GOSSIP_SELECT_OPTION

  alias ThistleTea.Game.World.Entity.Player.Gossip

  defstruct [:guid, :gossip_list_id, :code]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), gossip_list_id::little-size(32), rest::binary>> = payload

    %__MODULE__{
      guid: guid,
      gossip_list_id: gossip_list_id,
      code: rest
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, gossip_list_id: gossip_list_id}, state) do
    Gossip.select(state, guid, gossip_list_id)
  end
end
