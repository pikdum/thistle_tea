defmodule ThistleTea.Game.Network.Message.CmsgBuyItemReputationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
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
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

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
  end
end
