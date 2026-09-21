defmodule ThistleTea.Game.Player.VendorTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgBuyFailed
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "buy/4" do
    test "splits purchases into legal stacks and pays once" do
      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
      publish_vendor(vendor)
      owner = System.unique_integer([:positive, :monotonic])
      Registry.register(owner)
      template = %ItemTemplate{entry: 999_956, buy_price: 2, buy_count: 3, stackable: 5}
      :ets.insert(VendorLoader, {vendor_entry, [%VendorItem{index: 1, template: template, max_count: 0}]})
      character = character(30)
      character = %{character | id: owner, object: %{character.object | guid: owner}}
      state = %{ready: true, guid: owner, character: character}
      bought = Vendor.buy(state, vendor, template.entry, 4)
      items = Inventory.owned_items(bought.character.player, &ItemStore.get/1)
      assert Enum.map(items, & &1.item.stack_count) == [5, 5, 2]
      assert bought.character.player.coinage == 92

      on_exit(fn ->
        for {guid, %Item{item: %{owner: ^owner}}} <- :ets.tab2list(ItemStore), do: ItemStore.delete(guid)
        :ets.delete(VendorLoader, vendor_entry)
        :ets.delete(CharacterStore, owner)
        Metadata.delete(owner)
      end)
    end

    test "rechecks current rank and level without hiding ranked merchandise" do
      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
      publish_vendor(vendor_guid)
      template = %ItemTemplate{entry: 15_200, required_honor_rank: 8, required_level: 30, buy_price: 1}
      :ets.insert(VendorLoader, {vendor_entry, [%VendorItem{index: 1, template: template, max_count: 0}]})
      on_exit(fn -> :ets.delete(VendorLoader, vendor_entry) end)

      eligible = character(30)
      eligible = %{eligible | player: %{eligible.player | honor_rank: 8, highest_honor_rank: 18}}
      demoted = %{eligible | player: %{eligible.player | honor_rank: 7}}
      too_young = %{eligible | unit: %{eligible.unit | level: 29}}

      for character <- [demoted, too_young] do
        assert [%VendorItem{template: ^template}] = Vendor.visible_items(character, vendor_guid)
        state = %{ready: true, guid: 1, character: character}
        assert Vendor.buy(state, vendor_guid, template.entry, 1) == state
        assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyFailed{error: :rank_require}}}
      end

      eligible = %{eligible | player: %{eligible.player | coinage: 0}}
      state = %{ready: true, guid: 1, character: eligible}
      assert Vendor.buy(state, vendor_guid, template.entry, 1) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgBuyFailed{error: :not_enough_money}}}
    end
  end

  describe "condition policy" do
    test "hides, shows, and rejects a stale conditioned purchase" do
      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
      publish_vendor(vendor_guid)
      hidden_template = %ItemTemplate{entry: 1001, buy_price: 1}
      visible_template = %ItemTemplate{entry: 1002, buy_price: 1}
      condition = %Condition{entry: 1, type: :level, value1: 10, value2: 1}

      :ets.insert(VendorLoader, {
        vendor_entry,
        [
          %VendorItem{index: 1, template: hidden_template, max_count: 0, condition: condition},
          %VendorItem{index: 2, template: visible_template, max_count: 0}
        ]
      })

      on_exit(fn -> :ets.delete(VendorLoader, vendor_entry) end)

      assert [%VendorItem{index: 1, template: ^visible_template}] =
               Vendor.visible_items(character(9), vendor_guid)

      assert [
               %VendorItem{index: 1, template: ^hidden_template},
               %VendorItem{index: 2, template: ^visible_template}
             ] = Vendor.visible_items(character(10), vendor_guid)

      stale_state = %{ready: true, guid: 1, character: character(9)}
      assert Vendor.buy(stale_state, vendor_guid, hidden_template.entry, 1) == stale_state

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %SmsgBuyFailed{
                         vendor_guid: ^vendor_guid,
                         item_id: 1001,
                         error: :cant_find_item
                       }}}
    end

    test "denies unknown conditions" do
      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
      template = %ItemTemplate{entry: 2001, buy_price: 1}
      condition = %Condition{entry: 2, type: :item_with_bank, value1: 2001, value2: 1}

      :ets.insert(VendorLoader, {
        vendor_entry,
        [%VendorItem{index: 1, template: template, max_count: 0, condition: condition}]
      })

      on_exit(fn -> :ets.delete(VendorLoader, vendor_entry) end)

      assert Vendor.visible_items(character(60), vendor_guid) == []
    end
  end

  defp character(level) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        level: level,
        race: 1,
        class: 1,
        health: 100,
        max_health: 100,
        power1: 0,
        max_power1: 0,
        auras: []
      },
      player: %Player{
        coinage: 100,
        skills: %{},
        quest_log: %{},
        rewarded_quests: MapSet.new(),
        reputation: %Reputation{}
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(1), spellbook: %{}}
    }
  end

  defp publish_vendor(guid) do
    Metadata.put(guid, %{alive?: true, npc_flags: 4})
    SpatialHash.update(:mobs, guid, WorldRef.open(1), 2.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(guid)
      SpatialHash.remove(:mobs, guid)
    end)
  end
end
