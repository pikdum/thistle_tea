defmodule ThistleTea.Game.Entity.Logic.ItemWrappingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemWrapping
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Trade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  setup [:gift]

  describe "wrap/5" do
    test "spends one paper and changes identity in place", context do
      %{character: character, paper: paper, target: target, gift: gift, lookup: lookup} = context
      assert {:ok, changes} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, gift, lookup)
      wrapped = ChangeSet.get_item(changes, target.object.guid, lookup)
      assert changes.player == character.player
      assert ChangeSet.get_item(changes, paper.object.guid, lookup).item.stack_count == 1
      assert wrapped.object.guid == target.object.guid
      assert wrapped.object.entry == gift.entry
      assert Item.template(wrapped) == gift
      assert wrapped.item.flags == 8
      assert wrapped.item.gift_creator == 1
      assert wrapped.item.owner == 1
      assert wrapped.item.durability == 12
      assert Item.spell_charge(wrapped, 1) == -3
      assert Item.loot(wrapped) == nil
      assert {:ok, ^target} = Item.unwrap(wrapped)
      assert lookup.(paper.object.guid) == paper
      assert lookup.(target.object.guid) == target
    end

    test "works with full bags and consumes the final paper", context do
      paper = %{context.paper | item: %{context.paper.item | stack_count: 1}}
      fillers = for id <- 3..16, do: Item.build(%ItemTemplate{entry: 99}, 100 + id, owner: 1)
      items = Map.new([paper, context.target | fillers], &{&1.object.guid, &1})
      player = struct!(context.character.player, for(i <- 3..16, do: {String.to_atom("inv#{i}"), 100 + i}))
      character = %{context.character | player: player}
      assert {:ok, changes} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, context.gift, &Map.get(items, &1))
      assert changes.player.inv1 == 0
      assert changes.player.inv2 == context.target.object.guid
      assert ChangeSet.destroyed_items(changes) == [paper]
    end

    test "rejects restricted targets without spending paper", context do
      %{target: target, paper: paper, gift: gift, character: character} = context

      targets = [
        {Item.wrap(target, gift, 1), :wrapped_cant_be_wrapped},
        {%{target | item: %{target.item | flags: 1}}, :bound_cant_be_wrapped},
        {retarget(target, %{Item.template(target) | stackable: 20}), :stackable_cant_be_wrapped},
        {retarget(target, %{Item.template(target) | max_count: 1}), :unique_cant_be_wrapped},
        {Item.build(%ItemTemplate{entry: 4496, container_slots: 6}, 102, owner: 1), :bags_cant_be_wrapped},
        {Item.put_loot(target, %Loot{gold: 1}), :item_locked},
        {%{target | item: %{target.item | owner: 2}}, :item_not_found}
      ]

      for {target, reason} <- targets do
        items = %{101 => paper, 102 => target}
        assert {:error, ^reason} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, gift, &Map.get(items, &1))
        assert paper.item.stack_count == 2
      end
    end

    test "rejects equipment, wrapping itself, missing items and wrong paper mapping", context do
      %{character: character, gift: gift, lookup: lookup} = context
      equipped = %{character | player: %{character.player | mainhand: 102, inv2: 0}}
      assert {:error, :equipped_cant_be_wrapped} = ItemWrapping.wrap(equipped, {255, 23}, {255, 15}, gift, lookup)
      assert {:error, :wrapped_cant_be_wrapped} = ItemWrapping.wrap(character, {255, 23}, {255, 23}, gift, lookup)
      assert {:error, :item_not_found} = ItemWrapping.wrap(character, {255, 25}, {255, 24}, gift, lookup)
      assert {:error, :item_not_found} = ItemWrapping.wrap(character, {255, 23}, {255, 25}, gift, lookup)
      assert {:error, :item_not_found} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, nil, lookup)
      assert {:error, :item_not_found} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, %{gift | entry: 9}, lookup)
      invalid_paper = retarget(context.paper, %{Item.template(context.paper) | flags: 0})
      items = %{101 => invalid_paper, 102 => context.target}
      assert {:error, :item_not_found} = ItemWrapping.wrap(character, {255, 23}, {255, 24}, gift, &Map.get(items, &1))
    end

    test "rejects casting and death", context do
      %{character: character, gift: gift, lookup: lookup} = context
      casting = %{character | internal: %{character.internal | casting: %Cast{spell: %Spell{}}}}
      dead = %{character | unit: %{character.unit | health: 0}}
      assert {:error, :cant_do_right_now} = ItemWrapping.wrap(casting, {255, 23}, {255, 24}, gift, lookup)
      assert {:error, :you_are_dead} = ItemWrapping.wrap(dead, {255, 23}, {255, 24}, gift, lookup)
    end
  end

  describe "unwrap/3" do
    test "restores flags and identity without restoring expired enchantments or old ownership", context do
      target = Item.unlock(context.target) |> Item.put_temporary_enchantment(2623, 1_000, 1, 1_000, :token)
      wrapped = Item.wrap(target, context.gift, 1)
      {wrapped, nil} = Item.refresh_temporary_enchantment(wrapped, 2_000)
      wrapped = %{wrapped | item: %{wrapped.item | owner: 2, contained: 2, durability: 7}}
      character = %{context.character | object: %Object{guid: 2}, player: %Player{inv1: 102}}

      lookup = fn
        102 -> wrapped
        _ -> nil
      end

      assert {:ok, changes} = ItemWrapping.unwrap(character, wrapped, lookup)
      item = ChangeSet.get_item(changes, 102, lookup)
      assert item.object.entry == target.object.entry
      assert item.item.flags == 4
      assert item.item.owner == 2
      assert item.item.contained == 2
      assert item.item.gift_creator == 0
      assert item.item.durability == 7
      assert Item.temporary_enchantment(item) == nil
      assert Item.spell_charge(item, 1) == -3
      refute Map.has_key?(item.internal, :wrapped_item)
    end

    test "rejects foreign, missing and corrupt gifts without deleting them", context do
      %{character: character, target: target, gift: gift} = context
      wrapped = Item.wrap(target, gift, 1)
      foreign = %{wrapped | item: %{wrapped.item | owner: 2}}
      corrupt = %{wrapped | internal: Map.delete(wrapped.internal, :wrapped_item)}
      assert {:error, :dont_own_that_item} = ItemWrapping.unwrap(character, foreign, fn _ -> foreign end)
      assert {:error, :cant_do_right_now} = ItemWrapping.unwrap(character, corrupt, fn _ -> corrupt end)
      assert {:error, :cant_do_right_now} = ItemWrapping.unwrap(character, target, context.lookup)
      assert {:error, :item_not_found} = ItemWrapping.unwrap(%{character | player: %Player{}}, wrapped, fn _ -> nil end)
    end
  end

  describe "trade integration" do
    test "transfers the gift then restores the recipient's same item", context do
      wrapped = Item.wrap(context.target, context.gift, 1)
      first = %{context.character | player: %Player{inv1: 102, coinage: 100}}
      second = %{context.character | object: %Object{guid: 2}, player: %Player{coinage: 100}}

      lookup = fn
        102 -> wrapped
        _ -> nil
      end

      {:ok, trade} = :gift |> Trade.new(1, 2, 0) |> Trade.open(2)
      {:ok, trade} = Trade.put_item(trade, 1, 0, wrapped, 0)
      {:ok, trade} = Trade.accept(trade, 1, 200)
      {:ok, trade} = Trade.accept(trade, 2, 200)
      assert {:ok, exchange} = Trade.plan(trade, %{1 => first, 2 => second}, 200, lookup, fn _ -> nil end)
      received = ChangeSet.get_item(exchange.changes[2], 102, lookup)
      assert received.item.owner == 2
      assert received.item.gift_creator == 1
      assert Item.wrapped?(received)
      recipient = %{second | player: exchange.changes[2].player}
      lookup = &ChangeSet.get_item(exchange.changes[2], &1, lookup)
      assert {:ok, opened} = ItemWrapping.unwrap(recipient, received, lookup)
      item = ChangeSet.get_item(opened, 102, lookup)
      assert item.item.owner == 2
      assert item.item.gift_creator == 0
      assert item.object.entry == context.target.object.entry
      assert Item.spell_charge(item, 1) == -3
      assert item.item.enchantment == context.target.item.enchantment
      assert exchange.changes[1].player.inv1 == 0
    end
  end

  defp retarget(item, template), do: %{item | internal: %{item.internal | template: template}}

  defp gift(_context) do
    paper =
      Item.build(%ItemTemplate{entry: 5042, flags: 512, stackable: 10, wrapped_gift: 5043}, 101,
        owner: 1,
        stack_count: 2
      )

    gift = %ItemTemplate{entry: 5043, flags: 512}

    target =
      Item.build(%ItemTemplate{entry: 25, class: 2, max_durability: 20, spellid_1: 1, spellcharges_1: -5}, 102,
        owner: 1
      )
      |> Item.put_spell_charge(1, -3)
      |> Item.put_permanent_enchantment(1897)

    target = %{target | item: %{target.item | durability: 12, gift_creator: 0}}

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100},
      player: %Player{inv1: 101, inv2: 102},
      internal: %Internal{}
    }

    items = %{101 => paper, 102 => target}
    %{character: character, paper: paper, target: target, gift: gift, lookup: &Map.get(items, &1)}
  end
end
