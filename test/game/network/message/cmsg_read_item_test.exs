defmodule ThistleTea.Game.Network.Message.CmsgReadItemTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgReadItem
  alias ThistleTea.Game.World.Inbound
  alias ThistleTea.Game.World.ItemStore

  @backpack_start 23

  setup do
    ItemStore.init()
    :ok
  end

  describe "from_binary/1" do
    test "parses bag and slot" do
      assert %CmsgReadItem{bag: 255, slot: 23} = CmsgReadItem.from_binary(<<255, 23>>)
    end
  end

  describe "handle/2" do
    test "sends read ok for readable items" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      item = ItemStore.create(letter_template(), owner: player_guid)
      on_exit(fn -> ItemStore.delete(item.object.guid) end)
      guid = item.object.guid

      Inbound.handle(
        %CmsgReadItem{bag: Inventory.bag_0(), slot: @backpack_start},
        %{ready: true, character: character(player_guid, guid)}
      )

      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgReadItemOk{guid: ^guid}}}
    end

    test "sends an inventory failure for items without page text" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      item = ItemStore.create(%ItemTemplate{entry: 9001, name: "Rock"}, owner: player_guid)
      on_exit(fn -> ItemStore.delete(item.object.guid) end)

      Inbound.handle(
        %CmsgReadItem{bag: Inventory.bag_0(), slot: @backpack_start},
        %{ready: true, character: character(player_guid, item.object.guid)}
      )

      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgReadItemOk{}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{}}}
    end

    test "sends an inventory failure for empty slots" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

      Inbound.handle(
        %CmsgReadItem{bag: Inventory.bag_0(), slot: @backpack_start},
        %{ready: true, character: character(player_guid, nil)}
      )

      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{}}}
    end
  end

  defp letter_template do
    %ItemTemplate{entry: 9000, name: "Sealed Letter", page_text: 100}
  end

  defp character(player_guid, item_guid) do
    %Character{
      object: %Object{guid: player_guid},
      unit: %Unit{health: 100, max_health: 100, class: 8, race: 1, level: 1},
      player: %Player{inv1: item_guid},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end
end
