defmodule ThistleTea.Game.Player.BuybackTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Buyback
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Durability, as: DurabilityLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @entry 999_950

  setup [:vendor_inventory]

  describe "CMSG_SELL_ITEM and CMSG_BUYBACK_ITEM" do
    test "dispatches an identity-preserving sale and repurchase with private slot fields", context do
      %{state: state, item: item, vendor: vendor} = context
      assert Dispatch.implemented?(0x290)

      sell =
        Dispatch.to_message(%Packet{
          opcode: 0x1A0,
          payload: <<vendor::little-size(64), item.object.guid::little-size(64), 0>>
        })

      sold = Message.CmsgSellItem.handle(sell, state)
      assert sold.character.player.coinage == 1_050
      assert sold.character.player.inv1 == 0
      assert sold.character.player.buyback1 == item.object.guid
      guid = item.object.guid
      assert ItemStore.get(guid).item.contained == 0

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %UpdateObject{object_type: :item, update_type: :create_object2, object: %{guid: ^guid}}}}

      assert CharacterStore.get(state.guid).internal.buyback.entries[69].guid == guid
      buy = Dispatch.to_message(%Packet{opcode: 0x290, payload: <<vendor::little-size(64), 69::little-size(32)>>})
      assert %Message.CmsgBuybackItem{vendor_guid: ^vendor, slot: 69} = buy
      restored = Message.CmsgBuybackItem.handle(buy, sold)
      assert restored.character.player.coinage == 1_000
      assert restored.character.player.inv1 == guid
      assert restored.character.player.buyback1 == 0
      assert ItemStore.get(guid) == item
      assert Message.CmsgBuybackItem.handle(buy, restored) == restored
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyFailed{error: :cant_find_item}}}
    end

    test "settles completed item costs before selling the remaining stack", %{state: state, item: item, vendor: vendor} do
      item = %{item | item: %{item.item | stack_count: 5}}
      ItemStore.put(item)
      send(self(), {:consume_reagents, [{@entry, 2}]})
      sold = Buyback.sell(state, vendor, item.object.guid, 0)
      assert ItemStore.get(item.object.guid).item.stack_count == 3
      assert sold.character.player.coinage == 1_150
      assert sold.character.internal.buyback.entries[69].price == 150
    end

    test "quest inventory and equipped bonuses leave with the sale and return only when appropriate", context do
      %{state: state, item: item, vendor: vendor} = context
      quest = %Quest{id: 999_951, required_items: [{0, @entry, 1}]}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      on_exit(fn -> :ets.delete(QuestLoader, {:quest, quest.id}) end)
      {:ok, log} = QuestLog.add(%{}, quest.id)
      player = Inventory.equip(%{state.character.player | inv1: 0, quest_log: log}, :mainhand, item)
      character = Character.sync_equipment_stats(%{state.character | player: player})
      assert character.unit.base_min_damage == 30
      assert character.unit.max_health == 120
      assert Quests.needed_items(character) == MapSet.new()
      sold = Buyback.sell(%{state | character: character}, vendor, item.object.guid, 0)
      assert sold.character.unit.base_min_damage == 1.0
      assert sold.character.unit.max_health == 100
      assert sold.character.player.visible_item_16_0 == 0
      assert Quests.needed_items(sold.character) == MapSet.new([@entry])
      restored = Buyback.restore(sold, vendor, 69)
      assert restored.character.player.inv1 == item.object.guid
      assert restored.character.unit.base_min_damage == 1.0
      assert restored.character.unit.max_health == 100
      assert Quests.needed_items(restored.character) == MapSet.new()
    end

    test "selling a casting item interrupts it and logout discards buyback items", context do
      %{state: state, item: item, vendor: vendor} = context
      casting = %Cast{spell: %Spell{id: 999_952}, cast_item_guid: item.object.guid}
      state = %{state | character: %{state.character | internal: %{state.character.internal | casting: casting}}}
      sold = Buyback.sell(state, vendor, item.object.guid, 0)
      assert sold.character.internal.casting == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 999_952}}}
      logged_out = Buyback.logout(sold)
      assert logged_out.character.player.buyback1 == 0
      assert logged_out.character.internal.buyback.entries == %{}
      assert ItemStore.get(item.object.guid) == nil
      assert CharacterStore.get(state.guid).internal.buyback.entries == %{}
      assert Buyback.reset(logged_out.character).player.buyback1 == 0
    end

    test "invalid counts, bank access, active loot, and remote control cannot sell", context do
      %{state: state, item: item, vendor: vendor} = context
      assert Buyback.sell(state, vendor, item.object.guid, 2) == state

      banked = %{
        state
        | character: %{state.character | player: %{state.character.player | inv1: 0, bank1: item.object.guid}}
      }

      assert Buyback.sell(banked, vendor, item.object.guid, 0) == banked
      looting = %{state | loot_guid: item.object.guid}
      assert Buyback.sell(looting, vendor, item.object.guid, 0) == looting
      controlled = %{state | active_mover_guid: state.guid + 1}
      assert Buyback.sell(controlled, vendor, item.object.guid, 0) == controlled
      assert ItemStore.get(item.object.guid) == item
    end
  end

  describe "valid_vendor?/2" do
    test "requires a living vendor, matching world, interaction range, and a living player", context do
      %{state: state, item: item, vendor: vendor} = context
      assert Vendor.valid_vendor?(state.character, vendor)

      for metadata <- [%{alive?: false, npc_flags: 128}, %{alive?: true, npc_flags: 0}] do
        Metadata.put(vendor, metadata)
        refute Vendor.valid_vendor?(state.character, vendor)
        assert Buyback.sell(state, vendor, item.object.guid, 0) == state
      end

      Metadata.put(vendor, %{alive?: true, npc_flags: 128})
      SpatialHash.update(:mobs, vendor, WorldRef.open(0), 6.0, 0.0, 0.0)
      refute Vendor.valid_vendor?(state.character, vendor)
      assert Vendor.buy(state, vendor, @entry, 1) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyFailed{error: :distance_too_far}}}
      SpatialHash.update(:mobs, vendor, WorldRef.instance(0, 50), 2.0, 0.0, 0.0)
      refute Vendor.valid_vendor?(state.character, vendor)
      SpatialHash.update(:mobs, vendor, WorldRef.open(0), 2.0, 0.0, 0.0)
      dead = %{state.character | unit: %{state.character.unit | health: 0}}
      refute Vendor.valid_vendor?(dead, vendor)
      assert ItemStore.get(item.object.guid) == item
    end
  end

  describe "sale_penalty/2" do
    test "uses vendor-sale truncation without a reputation discount", %{item: item} do
      table = :ets.new(:sale_penalty, [:set])
      :ets.insert(table, [{{1, 2, 7}, 3}, {{:quality, 2}, 0.6}])
      item = %{item | item: %{item.item | max_durability: 10, durability: 9}}
      assert DurabilityLoader.sale_penalty(item, table) == 1
      assert DurabilityLoader.cost(item, 1.0, table) == 2
      item = %{item | item: %{item.item | durability: 10}}
      assert DurabilityLoader.sale_penalty(item, table) == 0
    end
  end

  defp vendor_inventory(_context) do
    owner = System.unique_integer([:positive, :monotonic])
    vendor = Guid.from_low_guid(:mob, 54, owner)

    template = %ItemTemplate{
      entry: @entry,
      sell_price: 50,
      class: 2,
      subclass: 7,
      inventory_type: 13,
      item_level: 1,
      dmg_min1: 30,
      dmg_max1: 40,
      stat_type1: 1,
      stat_value1: 20,
      stackable: 20
    }

    :ets.insert(ItemLoader, {@entry, template})
    item = ItemStore.create(template, owner: owner)
    Metadata.put(vendor, %{alive?: true, npc_flags: 128})
    SpatialHash.update(:mobs, vendor, WorldRef.open(0), 2.0, 0.0, 0.0)

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      player: %Player{coinage: 1_000, inv1: item.object.guid},
      internal: %Internal{},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, level: 50, race: 1, class: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      for {guid, %Item{item: %{owner: ^owner}}} <- :ets.tab2list(ItemStore), do: ItemStore.delete(guid)
      :ets.delete(ItemLoader, @entry)
      :ets.delete(CharacterStore, owner)
      Metadata.delete(vendor)
      Metadata.delete(owner)
      SpatialHash.remove(:mobs, vendor)
    end)

    %{state: %State{ready: true, guid: owner, character: character}, item: item, vendor: vendor}
  end
end
