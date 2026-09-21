defmodule ThistleTea.Game.Entity.Logic.TradeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Trade.Exchange
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemLifetime
  alias ThistleTea.Game.Entity.Logic.Trade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target

  setup [:build_trade]

  describe "negotiation" do
    test "only the recipient opens the requested trade" do
      trade = Trade.new(:trade, 1, 2, 0)
      assert {:error, :trade_canceled} = Trade.open(trade, 1)
      assert {:ok, %{phase: :open}} = Trade.open(trade, 2)
      assert {:error, :trade_canceled} = Trade.money(trade, 1, 1, 0)
    end

    test "item and money edits clear both acceptances", %{trade: trade, first: first} do
      assert {:ok, accepted} = Trade.accept(trade, 1, 200)
      assert accepted.offers[1].accepted?
      assert {:ok, changed} = Trade.money(accepted, 2, 100, 201)
      refute changed.offers[1].accepted?
      refute changed.offers[2].accepted?
      assert {:error, :back_to_trade} = Trade.accept(changed, 1, 400)
      assert {:ok, changed} = Trade.accept(changed, 1, 401)
      assert {:ok, changed} = Trade.put_item(changed, 2, 1, first, 402)
      refute changed.offers[1].accepted?
      assert {:ok, changed} = Trade.clear_item(changed, 2, 1, 403)
      assert changed.offers[2].items == %{}
    end

    test "rejects duplicate items and invalid slots", %{trade: trade, first: first} do
      assert {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:error, :trade_canceled} = Trade.put_item(trade, 1, 6, first, 0)
      assert {:error, :trade_canceled} = Trade.put_item(trade, 1, 7, first, 0)
      assert {:error, :trade_canceled} = Trade.money(trade, 1, -1, 0)
    end

    test "freezes negotiation after both acceptances", %{trade: trade} do
      assert {:ok, trade} = Trade.accept(trade, 1, 200)
      assert {:ok, trade} = Trade.accept(trade, 2, 201)
      assert trade.phase == :preparing
      assert {:error, :trade_canceled} = Trade.money(trade, 1, 10, 202)
      assert {:error, :trade_canceled} = Trade.accept(trade, 2, 203)
      reopened = Trade.reopen(trade)
      assert reopened.phase == :open
      refute reopened.offers[1].accepted?
      refute reopened.offers[2].accepted?
    end
  end

  describe "plan/5" do
    test "transfers a live deadline unchanged and rejects an expired offer", context do
      %{trade: trade, first: first, characters: characters, items: items} = context
      first = ItemLifetime.set_remaining(first, 1, -799)
      items = Map.put(items, first.object.guid, first)
      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:ok, exchange} = plan(trade, characters, &Map.get(items, &1))
      assert [received] = ChangeSet.placed_items(exchange.changes[2])
      assert received.item.owner == 2
      assert ItemLifetime.deadline(received) == 201
      {:ok, accepted} = Trade.accept(trade, 1, 200)
      {:ok, accepted} = Trade.accept(accepted, 2, 200)
      assert {:error, 1, :item_not_found} = Trade.plan(accepted, characters, 201, &Map.get(items, &1), fn _ -> nil end)
    end

    test "rejects items committed to an unfinished cast", context do
      %{trade: trade, first: first, characters: characters, lookup: lookup} = context
      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)

      for casting <- [
            %Cast{spell: %Spell{}, cast_item_guid: first.object.guid},
            %Cast{spell: %Spell{}, targets: Target.item(first.object.guid)},
            %Cast{spell: %Spell{reagents: [{first.object.entry, 1}]}}
          ] do
        caster = characters[1]
        caster = %{caster | internal: %{caster.internal | casting: casting}}
        assert {:error, 1, :item_locked} = plan(trade, %{characters | 1 => caster}, lookup)
      end
    end

    test "plans both inventories and coin balances while preserving item identity", context do
      %{trade: trade, first: first, second: second, characters: characters, lookup: lookup} = context
      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      {:ok, trade} = Trade.put_item(trade, 2, 0, second, 0)
      {:ok, trade} = Trade.money(trade, 1, 250, 0)
      {:ok, trade} = Trade.money(trade, 2, 75, 0)
      assert {:ok, %Exchange{} = exchange} = plan(trade, characters, lookup)
      assert exchange.changes[1].player.coinage == 825
      assert exchange.changes[2].player.coinage == 1175
      assert exchange.changes[1].player.inv1 == second.object.guid
      assert exchange.changes[2].player.inv1 == first.object.guid
      assert [received] = ChangeSet.placed_items(exchange.changes[1])
      assert received.item.owner == 1
      assert received.object.guid == second.object.guid
      assert characters[1].player.inv1 == first.object.guid
      assert lookup.(first.object.guid).item.owner == 1
    end

    test "outgoing items free bag capacity on both sides", context do
      %{trade: trade, first: first, second: second, characters: characters, items: items} = context
      {characters, items} = fill_bags(characters, items)
      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      {:ok, trade} = Trade.put_item(trade, 2, 0, second, 0)
      assert {:ok, exchange} = plan(trade, characters, &Map.get(items, &1))
      assert exchange.changes[1].player.inv1 == second.object.guid
      assert exchange.changes[2].player.inv1 == first.object.guid
    end

    test "rejects a full recipient inventory without producing either change set", context do
      %{trade: trade, first: first, characters: characters, items: items} = context
      {characters, items} = fill_bags(characters, items)
      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:error, 2, :inventory_full} = plan(trade, characters, &Map.get(items, &1))
      assert characters[1].player.inv1 == first.object.guid
    end

    test "retires a fully merged incoming GUID without deleting the destination stack", context do
      %{trade: trade, characters: characters} = context
      first = item(101, 100, 1, 5, 20)
      second = item(102, 100, 2, 10, 20)

      lookup = fn
        101 -> first
        102 -> second
        _ -> nil
      end

      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:ok, exchange} = plan(trade, characters, lookup)
      assert [merged] = ChangeSet.changed_items(exchange.changes[2])
      assert merged.item.stack_count == 15
      assert merged.item.owner == 2
      assert Enum.map(ChangeSet.destroyed_items(exchange.changes[2]), & &1.object.guid) == [101]
      assert exchange.changes[1].player.inv1 in [nil, 0]
    end

    test "places only the remainder of a partially merged transferred stack", context do
      %{trade: trade, characters: characters} = context
      first = item(101, 100, 1, 15, 20)
      second = item(102, 100, 2, 10, 20)

      lookup = fn
        101 -> first
        102 -> second
        _ -> nil
      end

      {:ok, trade} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:ok, exchange} = plan(trade, characters, lookup)
      assert [existing] = ChangeSet.changed_items(exchange.changes[2])
      assert [received] = ChangeSet.placed_items(exchange.changes[2])
      assert existing.item.stack_count == 20
      assert received.item.stack_count == 5
      assert received.item.owner == 2
      assert received.item.contained == 2
      assert received.object.guid == first.object.guid
    end

    test "keeps seventh-slot ownership even for a soulbound equipped item", context do
      %{trade: trade, first: first, characters: characters, items: items} = context
      first = %{first | item: %{first.item | flags: 1}}
      character = characters[1]
      character = %{character | player: %{character.player | inv1: 0, mainhand: first.object.guid}}
      characters = Map.put(characters, 1, character)
      items = Map.put(items, first.object.guid, first)
      {:ok, trade} = Trade.put_item(trade, 1, 6, first, 0)
      assert {:ok, exchange} = plan(trade, characters, &Map.get(items, &1))
      assert exchange.outgoing[1] == []
      assert exchange.changes[1].player.mainhand == first.object.guid
      assert ChangeSet.placed_items(exchange.changes[2]) == []
    end

    test "revalidates soulbinding, instance changes, ownership, and bank movement", context do
      %{trade: trade, first: first, characters: characters, items: items} = context
      {:ok, offered} = Trade.put_item(trade, 1, 0, first, 0)
      changed = %{first | item: %{first.item | stack_count: 2}}
      assert {:error, 1, :item_not_found} = plan(offered, characters, &Map.get(Map.put(items, 101, changed), &1))
      bound = %{first | item: %{first.item | flags: 1}}
      {:ok, offered} = Trade.put_item(trade, 1, 0, bound, 0)
      assert {:error, 1, :cant_drop_soulbound} = plan(offered, characters, &Map.get(Map.put(items, 101, bound), &1))
      character = characters[1]
      banked = %{character | player: %{character.player | inv1: 0, bank1: 101}}
      {:ok, offered} = Trade.put_item(trade, 1, 0, first, 0)
      assert {:error, 1, :item_not_found} = plan(offered, Map.put(characters, 1, banked), context.lookup)
    end

    test "rejects spent money and overflow without charging either side", context do
      %{trade: trade, characters: characters, lookup: lookup} = context
      {:ok, excessive} = Trade.money(trade, 1, 1_001, 0)
      assert {:error, 1, :not_enough_money} = plan(excessive, characters, lookup)
      character = characters[2]
      capped = %{character | player: %{character.player | coinage: 2_147_483_647}}
      {:ok, one_gold} = Trade.money(trade, 1, 1, 0)
      assert {:error, 2, :too_much_gold} = plan(one_gold, Map.put(characters, 2, capped), lookup)
    end
  end

  defp plan(trade, characters, lookup) do
    {:ok, trade} = Trade.accept(trade, 1, 200)
    {:ok, trade} = Trade.accept(trade, 2, 200)
    Trade.plan(trade, characters, 200, lookup, fn _ -> nil end)
  end

  defp build_trade(_context) do
    first = item(101, 100, 1)
    second = item(102, 200, 2)
    items = %{101 => first, 102 => second}

    characters =
      Map.new([{1, first}, {2, second}], fn {guid, item} ->
        {guid,
         %Character{
           id: guid,
           object: %Object{guid: guid},
           player: %Player{coinage: 1_000, inv1: item.object.guid},
           unit: %Unit{level: 50, health: 100},
           internal: %Internal{}
         }}
      end)

    {:ok, trade} = Trade.new(:trade, 1, 2, 0) |> Trade.open(2)
    %{trade: trade, first: first, second: second, items: items, characters: characters, lookup: &Map.get(items, &1)}
  end

  defp fill_bags(characters, items) do
    Enum.reduce([1, 2], {characters, items}, fn guid, {characters, items} ->
      Enum.reduce(2..16, {characters, items}, fn slot, {characters, items} ->
        item = item(guid * 1000 + slot, 300, guid)
        character = characters[guid]
        character = %{character | player: struct!(character.player, [{:"inv#{slot}", item.object.guid}])}
        {Map.put(characters, guid, character), Map.put(items, item.object.guid, item)}
      end)
    end)
  end

  defp item(guid, entry, owner, count \\ 1, stackable \\ 1) do
    Item.build(%ItemTemplate{entry: entry, stackable: stackable}, guid, owner: owner, stack_count: count)
  end
end
