defmodule ThistleTea.Game.Player.CharactersTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Player.Characters
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  setup do
    CharacterStore.init()
    ItemStore.init()
    ItemLoader.init()

    reset_counter_table(CharacterStore)
    reset_counter_table(ItemStore)
    :ets.delete_all_objects(ItemLoader)

    :ok
  end

  describe "create/1" do
    test "equips and stores playercreateinfo starting items" do
      cache_templates([
        template(25, inventory_type: 21, class: 2, subclass: 7, dmg_min1: 1.0, dmg_max1: 2.0),
        template(38, inventory_type: 4),
        template(39, inventory_type: 7),
        template(40, inventory_type: 8),
        template(117, inventory_type: 0, stackable: 20),
        template(2362, inventory_type: 14),
        template(6948, inventory_type: 0)
      ])

      assert {:ok, character} =
               Characters.create(
                 character(
                   "Starter",
                   [
                     %{item_id: 25, amount: 1},
                     %{item_id: 38, amount: 1},
                     %{item_id: 39, amount: 1},
                     %{item_id: 40, amount: 1},
                     %{item_id: 117, amount: 4},
                     %{item_id: 2362, amount: 1},
                     %{item_id: 6948, amount: 1}
                   ]
                 )
               )

      player = character.player

      assert ItemStore.get(player.mainhand).object.entry == 25
      assert ItemStore.get(player.body).object.entry == 38
      assert ItemStore.get(player.legs).object.entry == 39
      assert ItemStore.get(player.feet).object.entry == 40
      assert ItemStore.get(player.offhand).object.entry == 2362
      assert player.visible_item_16_0 == 25
      assert player.visible_item_17_0 == 2362
      assert Inventory.count_entry(player, 117, &ItemStore.get/1) == 4
      assert Inventory.count_entry(player, 6948, &ItemStore.get/1) == 1
      assert character.unit.health == character.unit.max_health
      assert character.unit.power1 == character.unit.max_power1
    end

    test "ignores missing starting item templates" do
      cache_templates([template(6948, inventory_type: 0)])

      assert {:ok, character} =
               Characters.create(
                 character("Missingitem", [
                   %{item_id: 999_999, amount: 1},
                   %{item_id: 6948, amount: 1}
                 ])
               )

      assert Inventory.count_entry(character.player, 6948, &ItemStore.get/1) == 1
      assert Inventory.count_entry(character.player, 999_999, &ItemStore.get/1) == 0
    end

    test "persists placed item state after a partial starting stack merge" do
      cache_templates([template(117, inventory_type: 0, stackable: 20)])

      assert {:ok, character} =
               Characters.create(
                 character("Partialstack", [
                   %{item_id: 117, amount: 19},
                   %{item_id: 117, amount: 5}
                 ])
               )

      stacks =
        character.player
        |> Inventory.owned_items(&ItemStore.get/1)
        |> Enum.filter(&(&1.object.entry == 117))
        |> Enum.map(& &1.item.stack_count)
        |> Enum.sort()

      assert stacks == [4, 20]
      assert Inventory.count_entry(character.player, 117, &ItemStore.get/1) == 24
    end

    test "clears equipped starter gear before applying a debug gear set" do
      cache_templates([
        template(25, inventory_type: 21, class: 2, subclass: 7),
        template(8190, inventory_type: 13, class: 2, subclass: 7)
      ])

      assert {:ok, character} =
               Characters.create(
                 character("Bettergear", [
                   %{item_id: 25, amount: 1}
                 ])
               )

      character =
        character
        |> Characters.clear_equipment()
        |> Characters.assign_items([8190])

      assert ItemStore.get(character.player.mainhand).object.entry == 8190
      assert Inventory.count_entry(character.player, 25, &ItemStore.get/1) == 0
    end
  end

  defp reset_counter_table(table) do
    :ets.delete_all_objects(table)
    :ets.insert(table, {:counter, 0})
  end

  defp cache_templates(templates) do
    Enum.each(templates, fn %ItemTemplate{entry: entry} = template ->
      :ets.insert(ItemLoader, {entry, template})
    end)
  end

  defp character(name, starting_items) do
    %Character{
      account_id: 1,
      object: %Object{},
      unit: %Unit{
        race: 1,
        class: 1,
        level: 1,
        health: 1,
        power1: 1,
        max_health: 50,
        max_power1: 20,
        strength: 10,
        agility: 10,
        stamina: 10,
        intellect: 10,
        spirit: 10,
        base_strength: 10,
        base_agility: 10,
        base_stamina: 10,
        base_intellect: 10,
        base_spirit: 10,
        base_health: 50,
        base_mana: 20,
        min_damage: 1.0,
        max_damage: 2.0,
        min_offhand_damage: 0.0,
        max_offhand_damage: 0.0,
        base_attack_time: 2000,
        offhand_attack_time: 2000
      },
      player: %Player{},
      internal: %Internal{name: name, starting_items: starting_items}
    }
  end

  defp template(entry, attrs) do
    struct(
      ItemTemplate,
      Keyword.merge(
        [
          entry: entry,
          allowable_class: -1,
          allowable_race: -1,
          stackable: 1,
          max_durability: 1
        ],
        attrs
      )
    )
  end
end
