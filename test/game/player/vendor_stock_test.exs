defmodule ThistleTea.Game.Player.VendorStockTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Entity.Data.VendorStock.Receipt
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgBuyFailed
  alias ThistleTea.Game.Network.Message.SmsgBuyItem
  alias ThistleTea.Game.Network.Message.SmsgItemPushResult
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.Player.VendorPurchase
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.VendorStock
  alias ThistleTea.Game.World.VendorStockStore
  alias ThistleTea.Game.WorldRef

  setup [:merchant]

  describe "buy/4" do
    test "depletes units but reports purchased bundles and rejects a stale sold-out request", context do
      %{state: state, vendor: vendor, item: item} = context
      bought = Vendor.buy(state, vendor, item.template.entry, 2)
      assert bought.character.player.coinage == 96
      assert Enum.map(owned(bought), & &1.item.stack_count) == [5, 1]
      assert [%VendorItem{available: 0}] = Vendor.visible_items(bought.character, vendor)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyItem{vendor_slot: 1, new_count: 0, count: 2}}}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgItemPushResult{count: 6}}}
      assert Vendor.buy(bought, vendor, item.template.entry, 1) == bought
      assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyFailed{error: :item_already_sold}}}
      assert VendorStockStore.pending(state.guid) == nil
      assert CharacterStore.get(state.guid).player.coinage == 96
    end

    test "money and capacity failures leave stock and inventory untouched", context do
      %{state: state, vendor: vendor, item: item} = context
      poor = %{state | character: %{state.character | player: %{state.character.player | coinage: 1}}}
      assert Vendor.buy(poor, vendor, item.template.entry, 1) == poor
      assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyFailed{error: :not_enough_money}}}

      filler = %ItemTemplate{entry: 999_944, stackable: 1}
      {:ok, full, _position} = Items.store(state, filler, 16)
      assert Vendor.buy(full, vendor, item.template.entry, 1) == full
      assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyFailed{error: :cant_carry_more}}}
      assert [%VendorItem{available: 6}] = Vendor.visible_items(full.character, vendor)
      assert full.character.player.coinage == 100
      assert length(owned(full)) == 16
      assert VendorStockStore.pending(state.guid) == nil
    end
  end

  describe "recover/1 and finish_recovery/1" do
    test "recovers an interrupted purchase exactly once without replenishing stock", context do
      %{state: state, vendor: vendor, item: item} = context
      character = %{state.character | player: %{state.character.player | coinage: 98}}
      {:ok, changes, position} = Items.plan_store(character, item.template, 3)

      offer = %Receipt{
        id: make_ref(),
        guid: state.guid,
        changes: changes,
        old_counts: %{},
        vendor_guid: vendor,
        vendor_item: item,
        count: 1,
        available: nil,
        position: position
      }

      CharacterStore.put(state.character)
      assert {:ok, receipt} = VendorStock.purchase(state.character.internal.world, offer)
      assert CharacterStore.get(state.guid).player.coinage == 100
      recovered = VendorPurchase.recover(CharacterStore.get(state.guid))
      assert recovered.player.coinage == 98
      assert recovered.internal.last_vendor_purchase_id == receipt.id
      assert VendorPurchase.recover(recovered) == recovered
      assert [item] = Inventory.owned_items(recovered.player, &ItemStore.get/1)
      assert item.item.stack_count == 3
      assert [%VendorItem{available: 3}] = Vendor.visible_items(recovered, vendor)
      recovered_state = VendorPurchase.finish_recovery(%{state | character: recovered})
      assert VendorPurchase.finish_recovery(recovered_state) == recovered_state
      assert VendorStockStore.pending(state.guid) == nil
      assert VendorPurchase.recover(recovered_state.character) == recovered_state.character
    end
  end

  defp merchant(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    entry = System.unique_integer([:positive, :monotonic])
    vendor = Guid.from_low_guid(:mob, entry, entry)
    world = WorldRef.open(1)
    Registry.register(guid)
    Metadata.put(vendor, %{alive?: true, npc_flags: 4})
    SpatialHash.update(:mobs, vendor, world, 2.0, 0.0, 0.0)

    item = %VendorItem{
      index: 1,
      template: %ItemTemplate{entry: 999_943, buy_count: 3, buy_price: 2, stackable: 5},
      max_count: 6,
      restock_seconds: 3_600
    }

    :ets.insert(VendorLoader, {entry, [item]})

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{level: 30, race: 1, class: 1, health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
      player: %Player{coinage: 100, skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new()},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, spellbook: %{}}
    }

    on_exit(fn ->
      for {key, %Item{item: %{owner: ^guid}}} <- :ets.tab2list(ItemStore), do: ItemStore.delete(key)
      :ets.delete(ItemStore, {:vendor_stock, {world, vendor, item.template.entry}})
      :ets.delete(ItemStore, {:vendor_purchase, guid})
      :ets.delete(CharacterStore, guid)
      :ets.delete(VendorLoader, entry)
      Metadata.delete(guid)
      Metadata.delete(vendor)
      SpatialHash.remove(:mobs, vendor)
    end)

    %{state: %{ready: true, guid: guid, character: character}, vendor: vendor, item: item}
  end

  defp owned(state), do: Inventory.owned_items(state.character.player, &ItemStore.get/1)
end
