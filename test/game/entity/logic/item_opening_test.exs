defmodule ThistleTea.Game.Entity.Logic.ItemOpeningTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.ItemOpening
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Trade
  alias ThistleTea.Game.Spell

  setup [:container]

  describe "validate/2" do
    test "rejects opening a container during fear or confusion", %{character: character, source: source} do
      for type <- [:mod_fear, :mod_confuse] do
        holder = %Holder{
          spell: %Spell{id: 1},
          auras: [%Aura{type: type}]
        }

        character = %{character | unit: %{character.unit | auras: [holder]}}
        assert {:error, :cant_do_right_now} = ItemOpening.validate(character, source)
      end
    end

    test "template loot flags do not unlock new lockboxes", %{character: character} do
      item = Item.build(%ItemTemplate{entry: 4632, flags: 4, lockid: 5}, 101, owner: 1)
      refute Item.unlocked?(item)
      assert {:error, :item_locked} = ItemOpening.validate(character, item)
      assert :ok = ItemOpening.validate(character, Item.unlock(item))
      assert {:error, :already_open} = ItemOpening.validate_unlock(Item.unlock(item))
    end

    test "rejects dead players, non-containers, bags and foreign ownership", %{character: character, source: source} do
      assert {:error, :you_are_dead} = ItemOpening.validate(%{character | unit: %{character.unit | health: 0}}, source)

      assert {:error, :dont_own_that_item} =
               ItemOpening.validate(character, %{source | item: %{source.item | owner: 2}})

      assert {:error, :cant_do_right_now} =
               ItemOpening.validate(character, Item.build(%ItemTemplate{entry: 1}, 11, owner: 1))

      bag = Item.build(%ItemTemplate{entry: 2, flags: 4, container_slots: 6}, 12, owner: 1)
      assert {:error, :cant_do_right_now} = ItemOpening.validate(character, bag)
    end
  end

  describe "claim/5, take_gold/3 and release/3" do
    test "retains partial loot and destroys an empty source only on release", %{
      character: character,
      source: source,
      reward: reward,
      get_item: get_item
    } do
      assert :unchanged = ItemOpening.release(character, source, get_item)
      assert {:ok, changes} = ItemOpening.claim(character, source, 0, reward, get_item)
      lookup = &ChangeSet.get_item(changes, &1, get_item)
      source = lookup.(source.object.guid)
      character = %{character | player: changes.player}
      assert Inventory.count_entry(character.player, 10, lookup) == 2
      assert Item.loot(source).gold == 25
      assert {:error, :already_looted} = ItemOpening.claim(character, source, 0, reward, lookup)
      assert :unchanged = ItemOpening.release(character, source, lookup)
      assert {:ok, 25, changes} = ItemOpening.take_gold(character, source, lookup)
      assert changes.player.coinage == 125
      lookup = &ChangeSet.get_item(changes, &1, lookup)
      source = lookup.(source.object.guid)
      character = %{character | player: changes.player}
      assert {:error, :cant_do_right_now} = ItemOpening.take_gold(character, source, lookup)
      assert {:ok, changes} = ItemOpening.release(character, source, lookup)
      assert changes.player.inv1 == 0
      assert [source] == ChangeSet.destroyed_items(changes)
    end

    test "full inventory leaves the source and its reward intact", %{
      character: character,
      source: source,
      reward: reward
    } do
      filler = for id <- 2..16, do: Item.build(%ItemTemplate{entry: 20}, 100 + id, owner: 1)
      items = Map.new([source | filler], &{&1.object.guid, &1})
      player = struct!(character.player, for(i <- 2..16, do: {String.to_atom("inv#{i}"), 100 + i}))
      character = %{character | player: player}
      assert {:error, :inventory_full} = ItemOpening.claim(character, source, 0, reward, &Map.get(items, &1))
      assert [%Loot.Item{looted: false}] = Item.loot(source).items
      assert Item.loot(source).gold == 25
    end
  end

  describe "generated loot inventory restrictions" do
    test "cannot trade, split or merge a rolled container", %{character: character} do
      template = %ItemTemplate{entry: 16_783, flags: 4, stackable: 20}
      source = Item.build(template, 101, owner: 1, stack_count: 3) |> Item.put_loot(%Loot{gold: 1})
      incoming = Item.build(template, 102, owner: 1, stack_count: 1)

      lookup = fn
        101 -> source
        _ -> nil
      end

      assert {:error, :item_locked} = Trade.validate_item(character, source, 0, 0, lookup, fn _ -> nil end)
      assert {:error, :item_locked, _, _} = Inventory.split(character.player, 1, {255, 23}, {255, 24}, incoming, lookup)
      assert {:ok, changes} = character.player |> Batch.new() |> Batch.add(incoming) |> Inventory.plan(lookup)
      assert changes.player.inv2 == 102
      assert ChangeSet.get_item(changes, 101, lookup).item.stack_count == 3
      assert Item.loot(ChangeSet.get_item(changes, 101, lookup)).gold == 1
    end
  end

  defp container(_context) do
    loot = %Loot{gold: 25, items: [%Loot.Item{slot: 0, item_id: 10, count: 2, display_id: 1, quality: 1}]}
    source = Item.build(%ItemTemplate{entry: 6351, flags: 4}, 101, owner: 1) |> Item.put_loot(loot)
    reward = Item.build(%ItemTemplate{entry: 10, stackable: 20}, 102, owner: 1, stack_count: 2)

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100},
      player: %Player{inv1: 101, coinage: 100},
      internal: %Internal{}
    }

    %{
      character: character,
      source: source,
      reward: reward,
      get_item: fn
        101 -> source
        _ -> nil
      end
    }
  end
end
