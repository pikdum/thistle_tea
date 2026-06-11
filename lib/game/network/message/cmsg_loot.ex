defmodule ThistleTea.Game.Network.Message.CmsgLoot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Player.Quests

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    with false <- Core.dead?(c),
         {:ok, %Loot{} = loot} <- Entity.call(guid, :loot_view) do
      Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: Quests.filter_loot(loot, c)})
      Map.put(state, :loot_guid, guid)
    else
      _ ->
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
