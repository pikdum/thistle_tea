defmodule ThistleTea.Game.Player.ItemCostsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.World.ItemStore

  describe "settle/1" do
    test "settles completed cast costs without consuming unrelated owner messages" do
      guid = System.unique_integer([:positive])
      first = ItemStore.create(%ItemTemplate{entry: 10_940, stackable: 20}, owner: guid, stack_count: 3)
      second = ItemStore.create(%ItemTemplate{entry: 10_938, stackable: 20}, owner: guid, stack_count: 2)
      oil = ItemStore.create(%ItemTemplate{entry: 20_744, spellid_1: 25_117, spellcharges_1: -5}, owner: guid)

      state = %State{
        guid: guid,
        ready: true,
        character: %Character{
          object: %Object{guid: guid},
          unit: %Unit{health: 100, max_health: 100},
          internal: %Internal{},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          player: %Player{inv1: first.object.guid, inv2: second.object.guid, inv3: oil.object.guid}
        }
      }

      send(self(), :unrelated_owner_message)
      send(self(), {:consume_reagents, [{10_940, 1}, {10_938, 1}]})
      send(self(), {:consume_cast_item, oil.object.guid})
      state = ItemCosts.settle(state)
      assert ItemStore.get(first.object.guid).item.stack_count == 2
      assert ItemStore.get(second.object.guid).item.stack_count == 1
      assert Item.spell_charge(ItemStore.get(oil.object.guid), 1) == -4
      assert state.character.player.inv3 == oil.object.guid
      assert_receive :unrelated_owner_message
      refute_receive {:consume_cast_item, _}
      refute_receive {:consume_reagents, _}
    end
  end
end
