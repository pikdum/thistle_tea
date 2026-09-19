defmodule ThistleTea.Game.Player.EnchantmentsTest do
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
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader

  @enchant 998_201
  @spell 998_202
  @dust 998_203

  setup [:inventory]

  describe "apply_permanent/5" do
    test "commits exact target, costs, skill, and visible bonuses together", %{state: state, item: item, spell: spell} do
      done = Enchantments.apply_permanent(state, item.object.guid, spell, @enchant)
      assert Item.active_enchantments(ItemStore.get(item.object.guid), Time.now()) == [{0, @enchant}]
      assert done.character.unit.max_health == 105
      assert done.character.unit.health == 100
      assert done.character.player.skills[333].value == 2
      assert Inventory.count_entry(done.character.player, @dust, &ItemStore.get/1) == 1
      assert done.character.player.visible_item_5_0 == item.object.entry + Bitwise.bsl(@enchant, 32)
      assert CharacterStore.get(state.guid).unit.max_health == 105
    end

    test "checks stale targets and missing materials without partial changes", %{state: state, item: item, spell: spell} do
      moved = %{state | character: %{state.character | player: %{state.character.player | chest: nil}}}
      assert Enchantments.apply_permanent(moved, item.object.guid, spell, @enchant) == moved
      spell = %{spell | reagents: [{@dust, 1}, {998_204, 1}]}
      assert Enchantments.apply_permanent(state, item.object.guid, spell, @enchant) == state
      assert Inventory.count_entry(state.character.player, @dust, &ItemStore.get/1) == 2
      assert ItemStore.get(item.object.guid) == item
    end

    test "replacement does not stack and bagged enchants grant no bonus", %{state: state, item: item, spell: spell} do
      first = Enchantments.apply_permanent(state, item.object.guid, spell, @enchant)
      second = Enchantments.apply_permanent(first, item.object.guid, spell, @enchant)
      assert second.character.unit.max_health == 105
      assert second.character.player.skills[333].value == 3
      bagged = %{second.character | player: %{second.character.player | chest: nil, inv2: item.object.guid}}
      assert Character.sync_equipment_stats(bagged).unit.max_health == 100
      restored = Enchantments.restore(second.character)
      assert restored.unit.max_health == 105
      assert restored.player.skills[333].value == 3
    end

    test "consumes an armor kit with the enchant without profession gains", %{state: state, item: item, spell: spell} do
      spell = %{spell | reagents: []}
      kit_guid = state.character.player.inv1
      done = Enchantments.apply_permanent(state, item.object.guid, spell, @enchant, kit_guid)
      assert done.character.unit.max_health == 105
      assert done.character.player.skills[333].value == 1
      assert ItemStore.get(kit_guid).item.stack_count == 1
    end

    test "removing enchanted equipment uses the normal inventory commit", %{state: state, item: item, spell: spell} do
      done = Enchantments.apply_permanent(state, item.object.guid, spell, @enchant)

      {:ok, changes} =
        done.character.player
        |> Batch.new()
        |> Batch.remove_item(item.object.guid, 1)
        |> Inventory.plan(&ItemStore.get/1)

      removed = InventoryUpdate.apply(done, {:ok, changes})
      assert removed.character.unit.max_health == 100
      assert ItemStore.get(item.object.guid) == nil
    end
  end

  describe "expire/3" do
    test "keeps permanent bonuses when temporary enchants expire", %{state: state, item: item, spell: spell} do
      done = Enchantments.apply_permanent(state, item.object.guid, spell, @enchant)
      now = Time.now()
      enchanted = ItemStore.get(item.object.guid) |> Item.put_temporary_enchantment(@enchant, 1000, 0, now - 1, :old)
      ItemStore.put(enchanted)
      assert Enchantments.expire(done, item.object.guid, :stale) == done
      expired = Enchantments.expire(done, item.object.guid, :old)
      assert expired.character.unit.max_health == 105
      assert Item.active_enchantments(ItemStore.get(item.object.guid), now) == [{0, @enchant}]
    end
  end

  defp inventory(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    item = ItemStore.create(%ItemTemplate{entry: 998_205, class: 4, inventory_type: 5, item_level: 10}, owner: guid)
    dust = ItemStore.create(%ItemTemplate{entry: @dust, stackable: 20}, owner: guid, stack_count: 2)

    :ets.insert(
      EnchantmentLoader,
      {{:enchantment, @enchant}, %ItemEnchantment{id: @enchant, effects: [%{type: 5, spell_id: 1, amount: 5}]}}
    )

    :ets.insert(EnchantmentLoader, {{:recipe, @spell}, %{skill_id: 333, yellow: 70, gray: 110}})
    player = Inventory.equip(%Player{inv1: dust.object.guid, skills: %{333 => %{value: 1, max: 75}}}, :chest, item)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: player,
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, level: 10, auras: []}
    }

    spell = %Spell{
      id: @spell,
      equipped_item_class: 4,
      reagents: [{@dust, 1}],
      effects: [%Effect{type: :enchant_item, misc_value: @enchant}]
    }

    on_exit(fn ->
      Enum.each([item.object.guid, dust.object.guid], &ItemStore.delete/1)
      :ets.delete(EnchantmentLoader, {:enchantment, @enchant})
      :ets.delete(EnchantmentLoader, {:recipe, @spell})
      :ets.delete(CharacterStore, guid)
    end)

    %{state: %State{guid: guid, character: character}, item: item, spell: spell}
  end
end
