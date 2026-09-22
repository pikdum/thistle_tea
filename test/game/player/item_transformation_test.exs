defmodule ThistleTea.Game.Player.ItemTransformationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.ItemCosts
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.ItemTransformation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader

  @entry 998_310
  @spell 998_311
  @enchant 998_312
  @reagent 998_313

  setup [:inventory]

  describe "complete/4" do
    test "replaces equipment, projects packets and stats, and survives restore", context do
      %{state: state, original: original, spell: spell} = context
      done = ItemTransformation.complete(state, original.object.guid, spell, @entry)
      replacement = ItemStore.get(done.character.player.mainhand)
      assert replacement.object.guid != original.object.guid
      assert replacement.object.entry == @entry
      assert replacement.item.durability == 40
      assert Item.spell_charge(replacement, 1) == -7
      assert ItemStore.get(original.object.guid) == nil
      assert done.character.unit.max_health == 105
      assert done.character.player.visible_item_16_0 == Item.visible_value(replacement)
      assert CharacterStore.get(state.guid).player.mainhand == replacement.object.guid
      assert Inventory.count_entry(done.character.player, @reagent, &ItemStore.get/1) == 1
      assert Item.temporary_enchantment(replacement) == Item.temporary_enchantment(original)
      assert Enchantments.restore(done.character).unit.max_health == 105
      assert Item.temporary_enchantment(ItemStore.get(replacement.object.guid)) == Item.temporary_enchantment(original)
      assert ItemTransformation.complete(done, original.object.guid, spell, @entry) == done
      assert Items.consume_cast_item(done, original.object.guid) == done
      assert Enchantments.expire(done, original.object.guid, :coating) == done

      guid = original.object.guid
      new_guid = replacement.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %{guid: ^new_guid}}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemEnchantTimeUpdate{item_guid: ^new_guid}}}

      expired = Item.put_temporary_enchantment(replacement, @enchant, 1, 3, Time.now() - 1, :coating)
      ItemStore.put(expired)
      expired_state = Enchantments.expire(done, new_guid, :coating)
      assert expired_state.character.unit.max_health == 100
      assert Item.temporary_enchantment(ItemStore.get(new_guid)) == nil
    end

    test "settles queued transformations before a trade snapshot", %{state: state, original: original, spell: spell} do
      send(self(), {:transform_item, original.object.guid, spell, @entry})
      send(self(), :unrelated)
      done = ItemCosts.settle(state)
      assert ItemStore.get(done.character.player.mainhand).object.entry == @entry
      refute_received {:transform_item, _, _, _}
      assert_received :unrelated
    end

    test "keeps source, reagents, and projections unchanged on invalid equipment", context do
      %{state: state, original: original, spell: spell, replacement: replacement} = context
      :ets.insert(ItemLoader, {@entry, %{replacement | allowable_class: 16}})
      assert ItemTransformation.complete(state, original.object.guid, spell, @entry) == state
      assert ItemStore.get(original.object.guid) == original
      assert Inventory.count_entry(state.character.player, @reagent, &ItemStore.get/1) == 2
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}}}
      refute_received {:"$gen_cast", {:send_packet, %UpdateObject{}}}
    end

    test "rejects missing reagents, lost ownership, mismatched spells, and exhausted source", context do
      %{state: state, original: original, spell: spell} = context

      assert ItemTransformation.complete(state, original.object.guid, %{spell | reagents: [{@reagent, 3}]}, @entry) ==
               state

      assert ItemTransformation.complete(state, original.object.guid, %{spell | id: 5}, @entry) == state
      detached = %{state | character: %{state.character | player: %{state.character.player | mainhand: 0}}}
      assert ItemTransformation.complete(detached, original.object.guid, spell, @entry) == detached
      ItemStore.put(%{original | item: %{original.item | owner: state.guid + 1}})
      assert ItemTransformation.complete(state, original.object.guid, spell, @entry) == state
      ItemStore.put(Item.put_spell_charge(original, 1, 0))
      assert ItemTransformation.complete(state, original.object.guid, spell, @entry) == state
      assert Inventory.count_entry(state.character.player, @reagent, &ItemStore.get/1) == 2
    end

    test "revalidates the current position and preserves broken items", %{
      state: state,
      original: original,
      spell: spell
    } do
      ItemStore.put(%{original | item: %{original.item | durability: 0}})

      state = %{
        state
        | character: %{state.character | player: %{state.character.player | mainhand: 0, bank1: original.object.guid}}
      }

      done = ItemTransformation.complete(state, original.object.guid, spell, @entry)
      assert Item.broken?(ItemStore.get(done.character.player.bank1))
      assert done.character.player.mainhand == 0
      assert done.character.unit.max_health == 100
    end
  end

  defp inventory(_context) do
    guid = System.unique_integer([:positive, :monotonic])

    source = %ItemTemplate{
      entry: @entry + 10,
      inventory_type: 17,
      max_durability: 100,
      spellid_1: @spell,
      spellcharges_1: -1
    }

    replacement = %ItemTemplate{
      entry: @entry,
      inventory_type: 17,
      max_durability: 80,
      spellid_1: @spell,
      spellcharges_1: -7
    }

    :ets.insert(ItemLoader, {@entry, replacement})

    :ets.insert(
      EnchantmentLoader,
      {{:enchantment, @enchant}, %ItemEnchantment{id: @enchant, effects: [%{type: 5, spell_id: 1, amount: 5}]}}
    )

    original = ItemStore.create(source, owner: guid)
    original = Item.put_temporary_enchantment(original, @enchant, 60_000, 3, Time.now() + 60_000, :coating)
    original = ItemStore.put(%{original | item: %{original.item | durability: 50}})
    reagent = ItemStore.create(%ItemTemplate{entry: @reagent, stackable: 20}, owner: guid, stack_count: 2)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: Inventory.equip(%Player{inv1: reagent.object.guid}, :mainhand, original),
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{class: 1, race: 1, health: 100, max_health: 100, base_health: 100, level: 60, auras: []}
    }

    spell = %Spell{
      id: @spell,
      reagents: [{@reagent, 1}],
      effects: [%Effect{type: :summon_change_item, misc_value: @entry}]
    }

    on_exit(fn ->
      for {_guid, %Item{item: %{owner: ^guid}} = item} <- :ets.tab2list(ItemStore),
          do: ItemStore.delete(item.object.guid)

      :ets.delete(ItemLoader, @entry)
      :ets.delete(EnchantmentLoader, {:enchantment, @enchant})
      :ets.delete(CharacterStore, guid)
    end)

    %{state: %State{guid: guid, character: character}, original: original, spell: spell, replacement: replacement}
  end
end
