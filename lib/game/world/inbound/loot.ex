defmodule ThistleTea.Game.World.Inbound.Loot do
  @moduledoc "Handles decoded loot client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.Outbound

  @votes %{0 => :pass, 1 => :need, 2 => :greed}

  def messages do
    [
      Message.CmsgAutostoreLootItem,
      Message.CmsgLoot,
      Message.CmsgLootMasterGive,
      Message.CmsgLootMoney,
      Message.CmsgLootRelease,
      Message.CmsgLootRoll
    ]
  end

  def handle(%Message.CmsgAutostoreLootItem{slot: slot}, state), do: Looting.take_item(state, slot)

  def handle(%Message.CmsgLoot{guid: guid}, state), do: Looting.open(state, guid)

  def handle(
        %Message.CmsgLootMasterGive{loot_guid: loot_guid, slot: slot, target: target},
        %{ready: true, loot_guid: loot_guid} = state
      ) do
    Looting.master_give(state, loot_guid, slot, target)
  end

  def handle(%Message.CmsgLootMasterGive{}, state), do: state

  def handle(%Message.CmsgLootMoney{}, state), do: Looting.take_money(state)

  def handle(%Message.CmsgLootRelease{}, %{ready: true} = state), do: Looting.release(state)

  def handle(%Message.CmsgLootRelease{guid: guid}, state) do
    Outbound.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end

  def handle(%Message.CmsgLootRoll{guid: loot_guid, slot: slot, vote: vote}, %{ready: true, guid: guid} = state) do
    case Map.fetch(@votes, vote) do
      {:ok, vote} -> Entity.loot_roll_vote(loot_guid, guid, slot, vote)
      :error -> :ok
    end

    state
  end

  def handle(%Message.CmsgLootRoll{}, state), do: state
end
