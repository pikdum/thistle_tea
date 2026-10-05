defmodule ThistleTea.Game.Core.Item.ItemLocationLimitsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Item.ItemLocationLimits
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:character]

  describe "allowed?/3" do
    test "map and zone bindings must both match" do
      map = Unique.integer()
      zone = Unique.integer()
      other_map = Unique.integer()
      other_zone = Unique.integer()
      assert ItemLocationLimits.allowed?(%ItemTemplate{}, map, zone)
      assert ItemLocationLimits.allowed?(%ItemTemplate{map: map}, map, other_zone)
      assert ItemLocationLimits.allowed?(%ItemTemplate{area: zone}, other_map, zone)
      assert ItemLocationLimits.allowed?(%ItemTemplate{map: map, area: zone}, map, zone)
      refute ItemLocationLimits.allowed?(%ItemTemplate{map: map, area: zone}, other_map, zone)
      refute ItemLocationLimits.allowed?(%ItemTemplate{map: map, area: zone}, map, other_zone)
    end
  end

  describe "plan/4" do
    test "removes equipment, keyring, backpack and bag contents without touching bank storage", context do
      character = context.character
      outside = Unique.integer()
      weapon = item(character, map: outside, inventory_type: 13)
      key = item(character, area: outside, class: 13)
      backpack = item(character, area: outside)
      banked = item(character, area: outside)
      ordinary = item(character)
      bag = item(character, class: 1, inventory_type: 18, container_slots: 4)
      child = item(character, area: outside)
      child = %{child | item: %{child.item | contained: bag.object.guid, stack_count: 3}}
      bag = %{bag | container: %{bag.container | slot_1: child.object.guid}}

      player = %Player{
        keyring_slots: 4,
        mainhand: weapon.object.guid,
        keyring1: key.object.guid,
        inv1: backpack.object.guid,
        inv2: ordinary.object.guid,
        bank1: banked.object.guid,
        bag1: bag.object.guid
      }

      character = %{character | player: player}
      get_item = lookup([weapon, key, backpack, banked, ordinary, bag, child])
      assert {:ok, changes} = ItemLocationLimits.plan(character, context.zone, :online, get_item)
      assert MapSet.new(Map.keys(changes.destroyed)) == MapSet.new([weapon, key, backpack, child], & &1.object.guid)
      assert changes.player.mainhand == 0
      assert changes.player.keyring1 == 0
      assert changes.player.inv1 == 0
      assert changes.player.inv2 == ordinary.object.guid
      assert changes.player.bank1 == banked.object.guid
      assert changes.changed[bag.object.guid].container.slot_1 == 0
      assert get_item.(child.object.guid) == child
    end

    test "destroys a restricted bag's unrestricted contents before removing the bag", context do
      bag = item(context.character, area: Unique.integer(), class: 1, inventory_type: 18, container_slots: 4)
      child = item(context.character, flags: 8)
      child = %{child | item: %{child.item | contained: bag.object.guid}}
      bag = %{bag | container: %{bag.container | slot_1: child.object.guid}}
      character = %{context.character | player: %Player{bag1: bag.object.guid}}
      assert {:ok, changes} = ItemLocationLimits.plan(character, context.zone, :online, lookup([bag, child]))
      assert MapSet.new(Map.keys(changes.destroyed)) == MapSet.new([bag.object.guid, child.object.guid])
      assert changes.player.bag1 == 0
      assert ChangeSet.changed_items(changes) == []
    end

    test "login includes bank items while corpses and ghosts retain every item", context do
      item = item(context.character, area: Unique.integer())
      character = %{context.character | player: %Player{bank1: item.object.guid}}
      get_item = lookup([item])
      assert {:ok, online} = ItemLocationLimits.plan(character, context.zone, :online, get_item)
      assert online.destroyed == %{}
      assert {:ok, login} = ItemLocationLimits.plan(character, context.zone, :login, get_item)
      assert login.player.bank1 == 0

      for dead <- [
            %{character | unit: %{character.unit | health: 0}},
            %{character | unit: %{character.unit | health: 1}, player: %{character.player | flags: 0x10}}
          ],
          phase <- [:online, :login] do
        assert {:ok, retained} = ItemLocationLimits.plan(dead, context.zone, phase, get_item)
        assert retained.player == dead.player
        assert retained.destroyed == %{}
      end
    end

    test "a stale reference cannot remove another owner's item", context do
      item = item(context.character, area: Unique.integer())
      item = %{item | item: %{item.item | owner: Unique.integer()}}
      character = %{context.character | player: %Player{inv1: item.object.guid}}
      assert {:ok, changes} = ItemLocationLimits.plan(character, context.zone, :online, lookup([item]))
      assert changes.destroyed == %{}
      assert changes.player == character.player
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: Unique.integer()},
      player: %Player{},
      unit: %Unit{health: 100},
      internal: %Internal{world: WorldRef.open(Unique.integer())}
    }

    %{character: character, zone: Unique.integer()}
  end

  defp item(character, attrs \\ []) do
    template = struct!(%ItemTemplate{entry: Unique.integer(), stackable: 20}, attrs)
    Item.build(template, Guid.from_low_guid(:item, Unique.integer()), owner: character.object.guid)
  end

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end
end
