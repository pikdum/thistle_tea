defmodule ThistleTea.Game.Network.Message.CmsgBuyItemReputationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.Reputation
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgBuyItem
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  describe "handle/2" do
    test "rejects purchases below the item's required reputation rank" do
      previous_catalog = ReputationLoader.catalog()
      definition = %Definition{id: 529, index: 13, variants: [%Variant{}]}
      catalog = %Catalog{factions: %{529 => definition}}
      ReputationLoader.put_catalog(catalog)

      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)

      template = %ItemTemplate{
        entry: 1_234,
        buy_price: 1,
        required_reputation_faction: 529,
        required_reputation_rank: 4
      }

      :ets.insert(VendorLoader, {vendor_entry, [%{index: 1, template: template, max_count: 0}]})

      on_exit(fn ->
        ReputationLoader.put_catalog(previous_catalog)
        :ets.delete(VendorLoader, vendor_entry)
      end)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{race: 1, class: 1},
        player: %Player{coinage: 100, reputation: Reputation.initialize(catalog, 1, 1)},
        internal: %Internal{}
      }

      state = %{ready: true, guid: 1, character: character}
      message = %CmsgBuyItem{vendor_guid: vendor_guid, item_id: template.entry, count: 1}

      assert CmsgBuyItem.handle(message, state) == state

      assert_receive {:"$gen_cast",
                      {:send_packet,
                       %Message.SmsgBuyFailed{
                         vendor_guid: ^vendor_guid,
                         item_id: 1_234,
                         error: :reputation_require
                       }}}
    end

    test "rounds the discount after multiplying the purchase count" do
      previous_catalog = ReputationLoader.catalog()
      definition = %Definition{id: 72, index: 19, variants: [%Variant{}]}
      catalog = %Catalog{factions: %{72 => definition}}
      ReputationLoader.put_catalog(catalog)

      vendor_entry = System.unique_integer([:positive, :monotonic])
      vendor_guid = Guid.from_low_guid(:mob, vendor_entry, vendor_entry)
      player_id = System.unique_integer([:positive, :monotonic])
      player_guid = Guid.from_low_guid(:player, player_id)
      template = %ItemTemplate{entry: 1_235, buy_price: 25}

      :ets.insert(VendorLoader, {vendor_entry, [%{index: 1, template: template, max_count: 0}]})
      Metadata.put(vendor_guid, %{faction_template: %FactionTemplate{faction: 72}})

      on_exit(fn ->
        ReputationLoader.put_catalog(previous_catalog)
        :ets.delete(VendorLoader, vendor_entry)
        Metadata.delete(vendor_guid)
      end)

      reputation = Reputation.initialize(catalog, 1, 1)
      {reputation, _changes} = Reputation.set(reputation, catalog, 72, 9_000, %{race: 1, class: 1})

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{race: 1, class: 1, level: 10},
        player: %Player{coinage: 100, reputation: reputation},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      }

      state = %{ready: true, guid: player_guid, character: character}
      message = %CmsgBuyItem{vendor_guid: vendor_guid, item_id: template.entry, count: 2}

      state = CmsgBuyItem.handle(message, state)

      assert state.character.player.coinage == 55
      item_guid = state.character.player.inv1
      assert ItemStore.get(item_guid).item.stack_count == 2
      ItemStore.delete(item_guid)
    end
  end
end
