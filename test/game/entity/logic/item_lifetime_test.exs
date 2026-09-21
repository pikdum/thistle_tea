defmodule ThistleTea.Game.Entity.Logic.ItemLifetimeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemLifetime

  describe "start/2" do
    test "starts once, rounds client seconds up, and expires at the exact deadline" do
      item = timed(101) |> ItemLifetime.start(-50_000)
      assert ItemLifetime.deadline(item) == 250_000
      assert ItemLifetime.start(item, 1_000) == item
      assert ItemLifetime.project(item, 249_001).item.duration == 1
      refute ItemLifetime.expired?(item, 249_999)
      assert ItemLifetime.expired?(item, 250_000)
      assert ItemLifetime.project(item, 260_000).item.duration == 0
      permanent = Item.build(%ItemTemplate{entry: 1}, 102, owner: 1)
      assert ItemLifetime.start(permanent, 0) == permanent
      refute ItemLifetime.expired?(permanent, 1_000_000)
    end

    test "splitting preserves the original deadline on both stacks" do
      source = timed(101, stackable: 20) |> ItemLifetime.start(0)
      source = %{source | item: %{source.item | stack_count: 10}}
      fresh = timed(102, stackable: 20)
      fresh = %{fresh | item: %{fresh.item | stack_count: 3}}
      player = %Player{inv1: source.object.guid}

      assert {:ok, result, %Item{} = placed} =
               Inventory.split(player, 1, {255, 23}, {255, 24}, fresh, lookup([source]))

      assert Enum.map([placed | result.items], &ItemLifetime.deadline/1) == [300_000, 300_000]
      assert Enum.sort(Enum.map([placed | result.items], & &1.item.stack_count)) == [3, 7]
    end

    test "wrapping and unwrapping preserve the same deadline" do
      item = timed(101) |> ItemLifetime.start(0)
      wrapped = Item.wrap(item, %ItemTemplate{entry: 5043, flags: 512}, 1)
      assert ItemLifetime.deadline(wrapped) == 300_000
      assert {:ok, unwrapped} = Item.unwrap(wrapped)
      assert ItemLifetime.deadline(unwrapped) == ItemLifetime.deadline(item)
      assert unwrapped.object == item.object
      assert {:ok, changes} = ItemLifetime.plan(character(%Player{inv1: 101}), 300_000, :online, lookup([wrapped]))
      assert Map.keys(changes.destroyed) == [101]
    end
  end

  describe "suspend/2" do
    test "ordinary items pause with millisecond precision while real-time items continue" do
      ordinary = timed(101) |> ItemLifetime.start(0)
      realtime = timed(102, flags: 0x10000) |> ItemLifetime.start(0)
      paused = ItemLifetime.suspend(ordinary, 100_111)
      assert ItemLifetime.deadline(paused) == nil
      assert paused.item.duration == 200
      assert ItemLifetime.remaining_ms(paused, 900_000) == 199_889
      assert ItemLifetime.deadline(ItemLifetime.start(paused, 900_000)) == 1_099_889
      assert ItemLifetime.suspend(realtime, 100_111) == realtime
      assert ItemLifetime.expired?(realtime, 900_000)
    end
  end

  describe "plan/4" do
    test "pausing a surviving bag cannot restore an expired child's inventory slot" do
      bag = timed(101, class: 1, inventory_type: 18, container_slots: 4) |> ItemLifetime.start(0)
      child = timed(102) |> ItemLifetime.set_remaining(1, 0)
      child = %{child | item: %{child.item | contained: 101}}
      bag = %{bag | container: %{bag.container | slot_1: 102}}
      assert {:ok, changes} = ItemLifetime.plan(character(%Player{bag1: 101}), 1_000, :logout, lookup([bag, child]))
      assert Map.keys(changes.destroyed) == [102]
      assert changes.changed[101].container.slot_1 == 0
      assert ItemLifetime.deadline(changes.changed[101]) == nil
      assert ItemLifetime.remaining_ms(changes.changed[101], 2_000) == 299_000
    end

    test "removes expired equipment, bag contents and bank items in one plan" do
      weapon = timed(101, inventory_type: 13) |> ItemLifetime.start(0)
      banked = timed(102) |> ItemLifetime.start(0)
      carried = timed(103) |> ItemLifetime.start(0)
      bag = Item.build(%ItemTemplate{entry: 2, class: 1, container_slots: 4, inventory_type: 18}, 104, owner: 1)
      bag = %{bag | container: %{bag.container | slot_1: carried.object.guid}}
      carried = %{carried | item: %{carried.item | contained: bag.object.guid}}
      player = %Player{mainhand: 101, bank1: 102, bag1: 104}
      get_item = lookup([weapon, banked, carried, bag])
      assert {:ok, unchanged} = ItemLifetime.plan(character(player), 299_999, :online, get_item)
      assert unchanged.destroyed == %{}
      assert {:ok, expired} = ItemLifetime.plan(character(player), 300_000, :online, get_item)
      assert Enum.sort(Map.keys(expired.destroyed)) == [101, 102, 103]
      assert expired.player.mainhand == 0
      assert expired.player.bank1 == 0
      assert expired.changed[104].container.slot_1 == 0
      assert get_item.(101) == weapon
    end

    test "destroys a timed bag's contents before the bag, bypassing manual restrictions" do
      bag = timed(101, class: 1, inventory_type: 18, container_slots: 4) |> ItemLifetime.start(0)
      child = Item.build(%ItemTemplate{entry: 2, flags: 8}, 102, owner: 1)
      child = %{child | item: %{child.item | contained: 101}}
      bag = %{bag | container: %{bag.container | slot_1: 102}}
      assert {:ok, changes} = ItemLifetime.plan(character(%Player{bag1: 101}), 300_000, :online, lookup([bag, child]))
      assert Enum.sort(Map.keys(changes.destroyed)) == [101, 102]
      assert changes.player.bag1 == 0
      assert changes.changed == %{}
    end

    test "login removes conjured items only after more than fifteen minutes offline" do
      conjured = Item.build(%ItemTemplate{entry: 1, flags: 2}, 101, owner: 1)
      normal = Item.build(%ItemTemplate{entry: 2}, 102, owner: 1)
      character = %{character(%Player{bank1: 101, inv1: 102}) | internal: %Internal{item_logout_at: 0}}
      get_item = lookup([conjured, normal])
      assert {:ok, retained} = ItemLifetime.plan(character, 900_000, :login, get_item)
      assert retained.destroyed == %{}
      assert {:ok, removed} = ItemLifetime.plan(character, 900_001, :login, get_item)
      assert Map.keys(removed.destroyed) == [101]
      assert removed.player.inv1 == 102
      assert {:ok, online} = ItemLifetime.plan(character, 900_001, :online, get_item)
      assert online.destroyed == %{}
    end

    test "login resumes ordinary budgets and deletes overdue real-time items" do
      ordinary = timed(101) |> ItemLifetime.start(0)
      realtime = timed(102, flags: 0x10000) |> ItemLifetime.start(0)
      character = character(%Player{inv1: 101, bank1: 102})
      assert {:ok, logout} = ItemLifetime.plan(character, 10_001, :logout, lookup([ordinary, realtime]))
      assert [%Item{} = paused] = ChangeSet.changed_items(logout)
      assert {:ok, login} = ItemLifetime.plan(character, 800_000, :login, lookup([paused, realtime]))
      assert Map.keys(login.destroyed) == [102]
      assert ItemLifetime.deadline(login.changed[101]) == 1_089_999
    end

    test "an old owner's inventory reference cannot expire a transferred item" do
      transferred = timed(101) |> ItemLifetime.start(0)
      transferred = %{transferred | item: %{transferred.item | owner: 2, contained: 2}}
      assert {:ok, changes} = ItemLifetime.plan(character(%Player{inv1: 101}), 300_000, :online, lookup([transferred]))
      assert changes.destroyed == %{}
    end
  end

  defp timed(guid, attrs \\ []) do
    Item.build(struct!(%ItemTemplate{entry: guid, duration: 300}, attrs), guid, owner: 1)
  end

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end

  defp character(player), do: %Character{object: %Object{guid: 1}, player: player, internal: %Internal{}}
end
