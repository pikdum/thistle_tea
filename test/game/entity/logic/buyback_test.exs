defmodule ThistleTea.Game.Entity.Logic.BuybackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Buyback.Change
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Buyback
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemLifetime
  alias ThistleTea.Game.Network.UpdateObject

  setup [:inventory]

  describe "sell/7" do
    test "moves a full item with its identity, fields and exact sale value", %{
      character: character,
      item: item,
      items: items
    } do
      item = %{item | item: %{item.item | flags: 1, durability: 4, creator: 99}}
      items = Map.put(items, item.object.guid, item)
      assert {:ok, change} = sell(character, item.object.guid, 0, items)
      assert change.inventory.player.inv1 == 0
      assert change.inventory.player.coinage == 1_050
      assert change.inventory.player.buyback1 == item.object.guid
      assert change.buyback.entries[69].price == 50
      assert [sold] = ChangeSet.placed_items(change.inventory)
      assert sold.object == item.object
      assert sold.item.flags == 1
      assert sold.item.durability == 4
      assert sold.item.creator == 99
      assert sold.item.contained == 0
      assert Inventory.count_entry(change.inventory.player, item.object.entry, lookup(items)) == 0
      assert change.inventory.destroyed == %{}
    end

    test "partial sales split off the sold count without losing instance state", context do
      item = %{context.item | item: %{context.item.item | stack_count: 5, creator: 44}}
      item = item |> Item.put_spell_charge(1, -2) |> ItemLifetime.set_remaining(45, 0)
      items = Map.put(context.items, item.object.guid, item)
      assert {:ok, change} = sell(context.character, item.object.guid, 2, items, now: 1_000)
      assert [sold] = ChangeSet.placed_items(change.inventory)
      assert sold.object.guid == 999
      assert sold.item.stack_count == 2
      assert sold.item.creator == 44
      assert Item.spell_charge(sold, 1) == -2
      assert ItemLifetime.remaining_ms(sold, 800_000) == 44_000
      assert change.inventory.changed[item.object.guid].item.stack_count == 3
      assert ItemLifetime.deadline(change.inventory.changed[item.object.guid]) == 45_000
      assert change.inventory.player.coinage == 1_100
    end

    test "rejects foreign, banked, unsellable, expired and excessive-count items", context do
      %{character: character, item: item, items: items} = context
      assert {:error, :cant_find_item} = sell(character, 9999, 0, items)
      assert {:error, :cant_sell_item} = sell(character, item.object.guid, 2, items)
      foreign = %{item | item: %{item.item | owner: 2}}
      assert {:error, :you_dont_own_that_item} = sell(character, item.object.guid, 0, %{items | 101 => foreign})
      banked = %{character | player: %{character.player | inv1: 0, bank1: item.object.guid}}
      assert {:error, :cant_sell_item} = sell(banked, item.object.guid, 0, items)
      free = %{item | internal: %{item.internal | template: %{Item.template(item) | sell_price: 0}}}
      assert {:error, :cant_sell_item} = sell(character, item.object.guid, 0, %{items | 101 => free})
      expired = ItemLifetime.set_remaining(item, 1, 0)
      assert {:error, :cant_sell_item} = sell(character, item.object.guid, 0, %{items | 101 => expired}, now: 1_000)
      capped = %{character | player: %{character.player | coinage: 2_147_483_647}}
      assert {:error, :cant_sell_item} = sell(capped, item.object.guid, 0, items)
    end

    test "rejects a nonempty bag without removing its contents or paying money", %{character: character} do
      bag =
        Item.build(%ItemTemplate{entry: 2, class: 1, inventory_type: 18, container_slots: 4, sell_price: 5}, 101,
          owner: 1
        )

      child = Item.build(%ItemTemplate{entry: 3}, 102, owner: 1)
      bag = %{bag | container: %{bag.container | slot_1: child.object.guid}}
      character = %{character | player: %{character.player | inv1: 0, bag1: 101}}
      assert {:error, :only_empty_bag} = sell(character, 101, 0, %{101 => bag, 102 => child})
    end

    test "the thirteenth sale evicts only the oldest slot", %{character: character, item: item} do
      {character, items} =
        Enum.reduce(1..13, {character, %{}}, fn index, {character, items} ->
          next = %{item | object: %{item.object | guid: 100 + index}}
          character = %{character | player: %{character.player | inv1: next.object.guid}}
          items = Map.put(items, next.object.guid, next)
          {:ok, change} = sell(character, next.object.guid, 0, items, now: index * 1_000)
          if index == 13, do: assert(Map.keys(change.inventory.destroyed) == [101])
          apply_change(character, items, change)
        end)

      assert map_size(character.internal.buyback.entries) == 12
      assert map_size(items) == 12
      assert character.player.buyback1 == 113
      assert character.player.buyback12 == 112
      assert character.player.coinage == 1_650
    end

    test "reuses the first slot when it is the only hole after filling the last slot", context do
      {character, items} =
        Enum.reduce(1..11, {context.character, %{}}, fn index, {character, items} ->
          item = %{context.item | object: %{context.item.object | guid: 100 + index}}
          character = %{character | player: %{character.player | inv1: item.object.guid}}
          items = Map.put(items, item.object.guid, item)
          {:ok, change} = sell(character, item.object.guid, 0, items, now: index * 1_000)
          apply_change(character, items, change)
        end)

      {:ok, bought} = Buyback.restore(character, 69, 12_000, lookup(items))
      {character, items} = apply_change(character, items, bought)
      {:ok, resold} = sell(character, 101, 0, items, now: 13_000)
      {character, items} = apply_change(character, items, resold)
      assert character.player.buyback12 == 101
      assert character.player.buyback1 == 0
      next = %{context.item | object: %{context.item.object | guid: 120}}
      character = %{character | player: %{character.player | inv1: 120}}
      {:ok, sale} = sell(character, 120, 0, Map.put(items, 120, next), now: 14_000)
      assert sale.inventory.player.buyback1 == 120
      assert sale.inventory.destroyed == %{}
    end
  end

  describe "restore/4" do
    test "restores the sold GUID once for the stored price", context do
      {:ok, sale} = sell(context.character, 101, 0, context.items)
      {character, items} = apply_change(context.character, context.items, sale)
      assert {:ok, bought} = Buyback.restore(character, 69, 9_000, lookup(items))
      assert bought.inventory.player.coinage == 1_000
      assert bought.inventory.player.inv1 == 101
      assert bought.inventory.player.buyback1 == 0
      assert bought.inventory.player.buyback_prices == 0
      assert bought.inventory.player.buyback_timestamps == 0
      {character, items} = apply_change(character, items, bought)
      assert {:error, :cant_find_item} = Buyback.restore(character, 69, 10_000, lookup(items))

      for slot <- [0, 68, 81, 4_294_967_295],
          do: assert({:error, :cant_find_item} = Buyback.restore(character, slot, 10_000, lookup(items)))
    end

    test "money and capacity failures retain the sold item and buyback entry", context do
      {:ok, sale} = sell(context.character, 101, 0, context.items)
      {character, items} = apply_change(context.character, context.items, sale)
      poor = %{character | player: %{character.player | coinage: 49}}
      assert {:error, :not_enough_money} = Buyback.restore(poor, 69, 0, lookup(items))
      fillers = for slot <- 1..16, do: Item.build(%ItemTemplate{entry: 2}, 200 + slot, owner: 1)
      fields = Enum.with_index(fillers, 1) |> Enum.map(fn {item, slot} -> {:"inv#{slot}", item.object.guid} end)
      full = %{character | player: struct!(character.player, fields)}
      items = Map.merge(items, Map.new(fillers, &{&1.object.guid, &1}))
      assert {:error, :inventory_full} = Buyback.restore(full, 69, 0, lookup(items))
      assert full.internal.buyback.entries[69].guid == 101
      assert items[101].item.stack_count == 1
    end

    test "merging a repurchased stack retires its old GUID without duplicating items", context do
      item = %{context.item | item: %{context.item.item | stack_count: 5}}
      {:ok, sale} = sell(context.character, 101, 2, %{101 => item})
      {character, items} = apply_change(context.character, %{101 => item}, sale)
      assert {:ok, bought} = Buyback.restore(character, 69, 0, lookup(items))
      assert bought.inventory.changed[101].item.stack_count == 5
      assert Map.keys(bought.inventory.destroyed) == [999]
      assert bought.inventory.player.buyback1 == 0
      assert bought.inventory.player.coinage == 1_000
      {_, items} = apply_change(character, items, bought)
      assert Map.keys(items) == [101]
    end

    test "resumes both real-time item and temporary-enchantment budgets after buyback", context do
      template = %{Item.template(context.item) | flags: 0x10000}
      item = %{context.item | internal: %{context.item.internal | template: template}}

      item =
        item |> ItemLifetime.set_remaining(10, 0) |> Item.put_temporary_enchantment(55, 20_000, 3, 20_000, :original)

      {:ok, sale} = sell(context.character, 101, 0, %{101 => item}, now: 2_000)
      {character, items} = apply_change(context.character, %{101 => item}, sale)
      assert ItemLifetime.deadline(items[101]) == nil
      assert ItemLifetime.remaining_ms(items[101], 60_000) == 8_000
      assert {:ok, bought} = Buyback.restore(character, 69, 60_000, lookup(items))
      assert [restored] = ChangeSet.placed_items(bought.inventory)
      assert ItemLifetime.deadline(restored) == 68_000
      assert %{expires_at: 78_000, charges: 3, token: :original} = Item.temporary_enchantment(restored)
    end
  end

  describe "sale_price/3" do
    test "prorates expendable charges then subtracts undiscounted durability loss", %{item: item} do
      template = %{Item.template(item) | spellid_2: 9, spellcharges_2: -5, sell_price: 101}
      item = %{item | internal: %{item.internal | template: template}} |> Item.put_spell_charge(2, -2)
      assert {:ok, 80} = Buyback.sale_price(item, 2, fn _ -> 0 end)
      assert {:ok, 70} = Buyback.sale_price(item, 2, fn _ -> 10 end)
      assert {:ok, 1} = Buyback.sale_price(item, 2, fn _ -> 90 end)
      assert {:error, :cant_sell_item} = Buyback.sale_price(item, 2, fn _ -> nil end)
    end
  end

  describe "project/2 and clear/3" do
    test "packs private price and timestamp arrays and cleans up every retained item", context do
      {:ok, sale} = sell(context.character, 101, 0, context.items, now: -1_000)
      {character, items} = apply_change(context.character, context.items, sale)
      fields = Player.to_list(character.player)
      price = Enum.find(fields, &(elem(&1, 0) == :buyback_prices))
      timestamp = Enum.find(fields, &(elem(&1, 0) == :buyback_timestamps))
      assert <<50::little-size(32), 0::size(352)>> = UpdateObject.field(price)
      assert <<108_000::little-size(32), 0::size(352)>> = UpdateObject.field(timestamp)
      refute Enum.any?(Player.to_list(character.player, :other), &(elem(&1, 0) == :buyback_prices))
      clear = Buyback.clear(character, 10_000, lookup(items))
      assert clear.buyback.entries == %{}
      assert clear.inventory.player.buyback1 == 0
      assert Map.keys(clear.inventory.destroyed) == [101]
    end
  end

  defp inventory(_context) do
    item = Item.build(%ItemTemplate{entry: 1001, sell_price: 50, stackable: 20}, 101, owner: 1)
    character = %Character{object: %Object{guid: 1}, player: %Player{inv1: 101, coinage: 1_000}, internal: %Internal{}}
    %{character: character, item: item, items: %{101 => item}}
  end

  defp sell(character, guid, count, items, opts \\ []),
    do: Buyback.sell(character, guid, count, 999, Keyword.get(opts, :now, 0), lookup(items), fn _ -> 0 end)

  defp lookup(items), do: &Map.get(items, &1)

  defp apply_change(character, items, %Change{} = change) do
    items = Map.drop(items, Map.keys(change.inventory.destroyed))

    items =
      Enum.reduce(
        ChangeSet.changed_items(change.inventory) ++ ChangeSet.placed_items(change.inventory),
        items,
        &Map.put(&2, &1.object.guid, &1)
      )

    character = %{
      character
      | player: change.inventory.player,
        internal: %{character.internal | buyback: change.buyback}
    }

    {character, items}
  end
end
