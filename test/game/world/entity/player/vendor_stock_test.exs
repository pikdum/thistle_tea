defmodule ThistleTea.Game.World.Entity.Player.VendorStockTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.ItemProperty
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.Vendor.VendorItem
  alias ThistleTea.Game.Core.Vendor.VendorStock.Receipt
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgBuyFailed
  alias ThistleTea.Game.Network.Message.SmsgBuyItem
  alias ThistleTea.Game.Network.Message.SmsgInventoryChangeFailure
  alias ThistleTea.Game.Network.Message.SmsgItemCooldown
  alias ThistleTea.Game.Network.Message.SmsgItemPushResult
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Items
  alias ThistleTea.Game.World.Entity.Player.Vendor
  alias ThistleTea.Game.World.Entity.Player.VendorPurchase
  alias ThistleTea.Game.World.Entity.Registry
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemProperty, as: ItemPropertyLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.VendorStock
  alias ThistleTea.Game.World.VendorStockStore
  alias ThistleTea.Test.Unique

  setup [:merchant]

  describe "buy/4" do
    test "reports the retained property on every purchased equipment instance", context do
      %{state: state, vendor: vendor, item: item} = context
      property = %ItemProperty{id: 59_003, suffix: "of Stamina"}

      :ets.insert(ItemPropertyLoader, [
        {{:property, property.id}, property},
        {{:table, 999_943}, [{property.id, 100.0}]}
      ])

      item = %{item | template: %{item.template | stackable: 1, buy_count: 1, random_property: 999_943}}
      :ets.insert(VendorLoader, {Guid.entry(vendor), [item]})

      on_exit(fn ->
        :ets.delete(ItemPropertyLoader, {:property, property.id})
        :ets.delete(ItemPropertyLoader, {:table, 999_943})
      end)

      bought = Vendor.buy(state, vendor, item.template.entry, 2)
      assert length(owned(bought)) == 2
      assert Enum.all?(owned(bought), &(Item.random_property(&1) == property))

      for _ <- 1..2 do
        assert_receive {:"$gen_cast",
                        {:send_packet, %SmsgItemPushResult{count: 1, received: 1, random_property_id: 59_003}}}
      end
    end

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

  describe "buy_in_slot/6" do
    test "uses the selected backpack slot and retains it through recovery", %{state: state, vendor: vendor, item: item} do
      bought = Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, 30)
      assert bought.character.player.inv1 == nil
      assert bought.character.player.inv8 > 0
      assert bought.character.player.coinage == 98
      assert [stored] = owned(bought)
      assert stored.item.stack_count == 3
      assert stored.item.contained == state.guid
      assert [%VendorItem{available: 3}] = Vendor.visible_items(bought.character, vendor)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgItemPushResult{bag_slot: 255, item_slot: 30, count: 3}}}
      assert VendorPurchase.recover(CharacterStore.get(state.guid)) == bought.character
    end

    test "resolves equipped bag GUIDs and spills bundles into the same bag", context do
      %{state: state, vendor: vendor, item: item} = context

      bag =
        ItemStore.prepare(%ItemTemplate{entry: 999_945, class: 1, inventory_type: 18, container_slots: 4},
          owner: state.guid
        )

      ItemStore.put(bag)
      state = %{state | character: %{state.character | player: %{state.character.player | bag1: bag.object.guid}}}

      bought = Vendor.buy_in_slot(state, vendor, item.template.entry, 2, bag.object.guid, 2)
      bag = ItemStore.get(bag.object.guid)
      assert ItemStore.get(bag.container.slot_3).item.stack_count == 5
      assert ItemStore.get(bag.container.slot_1).item.stack_count == 1
      assert bought.character.player.inv1 == nil
      assert bought.character.player.coinage == 96
      assert_receive {:"$gen_cast", {:send_packet, %SmsgItemPushResult{bag_slot: 19, item_slot: 2, count: 6}}}
    end

    test "rejects occupied slots without spending stock, money or item rows", context do
      %{state: state, vendor: vendor, item: item} = context
      {:ok, state, _position} = Items.store(state, %ItemTemplate{entry: 999_944}, 1)
      before = owned(state)
      assert Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, 23) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 19}}}
      assert owned(state) == before
      assert [%VendorItem{available: 6}] = Vendor.visible_items(state.character, vendor)
      assert VendorStockStore.pending(state.guid) == nil
      assert CharacterStore.get(state.guid).player.coinage == 100
    end

    test "rejects bank slots and foreign or unequipped bag GUIDs", context do
      %{state: state, vendor: vendor, item: item} = context
      template = %ItemTemplate{entry: 999_945, class: 1, inventory_type: 18, container_slots: 4}
      bag = ItemStore.prepare(template, owner: state.guid)
      foreign = ItemStore.prepare(template, owner: state.guid + 1)
      ItemStore.put(bag)
      ItemStore.put(foreign)
      on_exit(fn -> ItemStore.delete(foreign.object.guid) end)
      player = %{state.character.player | inv1: bag.object.guid, bag1: foreign.object.guid, bank_bag1: bag.object.guid}
      state = %{state | character: %{state.character | player: player}}

      for guid <- [0, bag.object.guid, foreign.object.guid, state.guid + 1] do
        assert Vendor.buy_in_slot(state, vendor, item.template.entry, 1, guid, 0) == state
      end

      for slot <- [39, 63, 100] do
        assert Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, slot) == state
        assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 3}}}
      end

      assert [%VendorItem{available: 6}] = Vendor.visible_items(state.character, vendor)
      assert VendorStockStore.pending(state.guid) == nil
      refute_received {:"$gen_cast", {:send_packet, %SmsgBuyItem{}}}
    end

    test "equips into an empty slot despite a full backpack and starts stats, binding and cooldowns", context do
      %{state: state, vendor: vendor} = context
      {item, spell} = equipment_offer(context)
      {:ok, state, _position} = Items.store(state, %ItemTemplate{entry: 999_944}, 16)
      before = Time.now()
      bought = Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, 12)
      equipped = ItemStore.get(bought.character.player.trinket1)
      assert equipped.item.flags == 1
      assert equipped.item.contained == state.guid
      assert bought.character.unit.equipment_bonuses.stamina == 7
      assert bought.character.player.coinage == 98
      assert Cooldowns.ready_at(bought.character, spell) >= before + 30_000
      assert_receive {:"$gen_cast", {:send_packet, %SmsgItemCooldown{item_guid: guid, spell_id: spell_id}}}
      assert guid == equipped.object.guid
      assert spell_id == spell.id

      assert Vendor.buy_in_slot(bought, vendor, item.template.entry, 1, state.guid, 12) == bought
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 9}}}
      assert [%VendorItem{available: 5}] = Vendor.visible_items(bought.character, vendor)
    end

    test "equipment count, level, proficiency and combat failures preserve the purchase", context do
      %{state: state, vendor: vendor} = context
      {item, _spell} = equipment_offer(context)

      assert Vendor.buy_in_slot(state, vendor, item.template.entry, 2, state.guid, 12) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 20}}}

      put_offer(vendor, %{item | template: %{item.template | required_level: 60}})
      assert Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, 12) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 1, required_level: 60}}}

      put_offer(vendor, %{item | template: %{item.template | required_skill: 202, required_skill_rank: 100}})
      assert Vendor.buy_in_slot(state, vendor, item.template.entry, 1, state.guid, 12) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 8}}}

      put_offer(vendor, item)
      combat = %{state | character: %{state.character | internal: %{state.character.internal | in_combat: true}}}
      assert Vendor.buy_in_slot(combat, vendor, item.template.entry, 1, state.guid, 12) == combat
      assert_receive {:"$gen_cast", {:send_packet, %SmsgInventoryChangeFailure{code: 60}}}
      assert [%VendorItem{available: 6}] = Vendor.visible_items(state.character, vendor)
      assert owned(state) == []
      assert VendorStockStore.pending(state.guid) == nil
    end
  end

  describe "recover/1 and finish_recovery/1" do
    test "restores an interrupted equipment purchase with a single equip cooldown", context do
      %{state: state, vendor: vendor} = context
      {item, spell} = equipment_offer(context)
      character = %{state.character | player: %{state.character.player | coinage: 98}}

      {:ok, changes, position} =
        Items.plan_store(character, item.template, 1,
          destination: {255, 12},
          unit: character.unit,
          proficiency: Proficiency.all()
        )

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
      assert {:ok, _receipt} = VendorStock.purchase(character.internal.world, offer)
      before = Time.now()
      recovered = VendorPurchase.recover(CharacterStore.get(state.guid))
      assert recovered.player.trinket1 > 0
      assert recovered.player.coinage == 98
      assert recovered.unit.equipment_bonuses.stamina == 7
      assert Cooldowns.ready_at(recovered, spell) >= before + 30_000
      assert VendorPurchase.recover(recovered) == recovered
      assert [%VendorItem{available: 5}] = Vendor.visible_items(recovered, vendor)
      recovered_state = VendorPurchase.finish_recovery(%{state | character: recovered})
      assert VendorStockStore.pending(state.guid) == nil
      assert VendorPurchase.settle(recovered_state) == recovered_state
    end

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
    guid = Unique.integer()
    entry = Unique.integer()
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

  defp equipment_offer(%{item: item, vendor: vendor}) do
    spell = %Spell{id: 999_946}
    :ets.insert(SpellLoader, {{:spell, spell.id}, spell})
    on_exit(fn -> :ets.delete(SpellLoader, {:spell, spell.id}) end)

    template = %{
      item.template
      | buy_count: 1,
        stackable: 1,
        class: 4,
        inventory_type: 12,
        bonding: 2,
        stat_type1: 7,
        stat_value1: 7,
        spellid_1: spell.id
    }

    item = %{item | template: template}
    put_offer(vendor, item)
    {item, spell}
  end

  defp put_offer(vendor, item), do: :ets.insert(VendorLoader, {Guid.entry(vendor), [item]})
end
