defmodule ThistleTea.Game.Network.Message.CmsgLootMasterGive do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MASTER_GIVE

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Player.Looting

  defstruct [:loot_guid, :slot, :target]

  @impl ClientMessage
  def handle(
        %__MODULE__{loot_guid: loot_guid, slot: slot, target: target},
        %{ready: true, loot_guid: loot_guid} = state
      ) do
    giver = Looting.actor(state, loot_guid)
    recipient = Looting.remote_actor(target, loot_guid)

    case Entity.call(loot_guid, {:loot_master_give, giver, slot, recipient}) do
      :ok -> Network.send_packet(%Message.SmsgLootRemoved{slot: slot})
      _ -> :ok
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<loot_guid::little-size(64), slot::little-size(8), target::little-size(64)>> = payload

    %__MODULE__{
      loot_guid: loot_guid,
      slot: slot,
      target: target
    }
  end
end
