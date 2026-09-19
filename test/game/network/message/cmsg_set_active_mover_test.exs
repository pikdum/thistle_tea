defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMoverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.ItemLoot
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgSetActiveMover
  alias ThistleTea.Game.Network.Message.SmsgLootResponse
  alias ThistleTea.Game.Network.UpdateObject

  describe "from_binary/1" do
    test "parses mover guid" do
      assert %CmsgSetActiveMover{guid: 23} = CmsgSetActiveMover.from_binary(<<23::little-size(64)>>)
    end
  end

  describe "handle/2" do
    test "reopens retained item loot on initial login only" do
      source = Item.build(%ItemTemplate{entry: 14_113}, 42, owner: 23)
      pending = ItemLoot.new(source, %Loot{items: [%Loot.Item{slot: 0, item_id: 10_940, count: 2}]})

      character = %Character{
        object: %Object{guid: 23},
        unit: %Unit{health: 100},
        internal: %Internal{item_loot: pending}
      }

      session = %State{guid: 23, character: character, visibility_cells: MapSet.new()}
      message = %CmsgSetActiveMover{guid: 23}

      state = CmsgSetActiveMover.handle(message, session)
      assert state.loot_guid == 42
      assert state.loot_type == :item
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %Object{guid: 42}}}}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgLootResponse{guid: 42, loot_type: 2}}}
      assert CmsgSetActiveMover.handle(message, state) == state
      refute_receive {:"$gen_cast", {:send_packet, %SmsgLootResponse{}}}
    end

    test "marks matching player ready" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 23}, %State{guid: 23})

      assert state.ready
      assert state.active_mover_guid == 23
      refute_receive :spawn_objects
    end

    test "ignores mismatched mover" do
      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, %State{guid: 23})

      refute state.ready
      assert state.active_mover_guid == nil
      refute_receive :spawn_objects
    end

    test "accepts the character's controlled unit after entering the world" do
      character =
        %Character{unit: %Unit{}, internal: %Internal{}}
        |> Companion.activate(:possession, %EntityRef{guid: 24, entry: 1, spell_id: 126})

      session = %State{guid: 23, ready: true, character: character}

      state = CmsgSetActiveMover.handle(%CmsgSetActiveMover{guid: 24}, session)

      assert state.active_mover_guid == 24
    end
  end
end
