defmodule ThistleTea.Game.Network.Message.CmsgGossipSelectOption do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_SELECT_OPTION

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
end
