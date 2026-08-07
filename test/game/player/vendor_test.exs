defmodule ThistleTea.Game.Player.VendorTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgBuyFailed
  alias ThistleTea.Game.Player.Vendor
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.WorldRef

  describe "condition policy" do
    test "hides, shows, and rejects a stale conditioned purchase" do
      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
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
end
