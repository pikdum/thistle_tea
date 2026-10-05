defmodule ThistleTea.Game.World.Entity.Player.BattlegroundSupplies do
  @moduledoc "Plans a carried beacon or assault order before reserving its team's supplies."

  alias ThistleTea.Game.Core.Battleground.AlteracValley.Air
  alias ThistleTea.Game.Core.Battleground.AlteracValley.Ground
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Battleground.Match

  def take_beacon(state, entry, standing, opts \\ []),
    do: take(state, entry, standing, Air.beacon_item(entry), &Match.take_beacon/4, opts)

  def take_orders(state, entry, standing, opts \\ []),
    do: take(state, entry, standing, Ground.order_item(entry), &Match.take_orders/4, opts)

  defp take(%{character: %Character{} = character} = state, entry, standing, item_id, reserve, opts) do
    with pid when is_pid(pid) <-
           BattlegroundSystem.match_for_world(
             character.internal.world,
             Keyword.get(opts, :battleground_system, BattlegroundSystem)
           ),
         %ItemTemplate{} = template <- ItemLoader.get_cached_template(item_id),
         item = ItemStore.prepare(template, owner: character.object.guid),
         {:ok, changes} <- Inventory.plan(Batch.add(Batch.new(character.player), item), &ItemStore.get/1),
         {:ok, ^item_id} <- reserve.(pid, character.object.guid, entry, standing) do
      placement = ChangeSet.placement(changes, item.object.guid)
      {bag, slot} = placement.position
      state = InventoryUpdate.apply(state, {:ok, changes})

      Outbound.send_packet(%Message.SmsgItemPushResult{
        player_guid: character.object.guid,
        item_id: item_id,
        bag_slot: bag,
        item_slot: slot,
        count: 1,
        received: 1,
        show_in_chat: 1
      })

      Outbound.send_packet(%Message.SmsgGossipComplete{})
      %{state | gossip_menu_options: []}
    else
      {:error, reason} when reason != :unavailable -> InventoryUpdate.apply(state, {:error, reason, 0, 0})
      {:error, reason, first, second} -> InventoryUpdate.apply(state, {:error, reason, first, second})
      _unavailable -> state
    end
  end
end
