defmodule ThistleTea.Game.Network.Message.CmsgLootRelease do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_RELEASE

  alias ThistleTea.Game.Entity

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, loot_guid: loot_guid} = state) when is_integer(loot_guid) do
    Entity.call(loot_guid, :loot_release)
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: loot_guid})
    Map.delete(state, :loot_guid)
  end

  def handle(%__MODULE__{guid: guid}, state) do
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
