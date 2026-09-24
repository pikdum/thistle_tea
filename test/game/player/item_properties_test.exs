defmodule ThistleTea.Game.Player.ItemPropertiesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.SmsgItemPushResult
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Loader.ItemProperty, as: PropertyLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  @entry 998_360
  @property_id 59_001
  @other_property_id 59_002

  setup [:build_inventory]

  describe "give/3" do
    test "rolls each equipment instance and reports its selected property", %{state: state, template: template} do
      :rand.seed(:exsss, {1, 2, 3})
      expected = Enum.map(1..3, fn _ -> PropertyLoader.roll(template).id end)
      :rand.seed(:exsss, {1, 2, 3})
      granted = Items.give(state, @entry, 3)
      items = Inventory.owned_items(granted.character.player, &ItemStore.get/1)
      assert Enum.map(items, & &1.item.random_properties_id) == expected
      assert Enum.all?(items, &(&1.item.stack_count == 1))

      for property_id <- expected do
        assert_receive {:"$gen_cast", {:send_packet, %SmsgItemPushResult{count: 1, random_property_id: ^property_id}}}
      end
    end
  end

  describe "store/3" do
    test "preserves rolled loot through full bags and retries", %{state: state} do
      loot = LootLoader.generate_fixed([{@entry, 1}], 0)
      [reward] = loot.items
      assert %ItemProperty{} = reward.random_property
      full = fill_inventory(state)
      assert {:error, :inventory_full, ^full} = Items.store(full, reward, 1)

      :ets.insert(PropertyLoader, {{:table, @entry}, []})
      assert {:ok, stored, _position} = Items.store(state, reward, 1)
      [item] = Inventory.owned_items(stored.character.player, &ItemStore.get/1)
      assert Item.random_property(item) == reward.random_property
      assert item.item.random_properties_id == reward.random_property.id
      assert CharacterStore.get(stored.guid).player.inv1 == item.object.guid
    end

    test "an explicitly property-free reward does not reroll", %{state: state} do
      reward = %Loot.Item{item_id: @entry, count: 1}
      assert {:ok, stored, _position} = Items.store(state, reward, 1)
      [item] = Inventory.owned_items(stored.character.player, &ItemStore.get/1)
      assert Item.random_property(item) == nil
      assert (item.item.random_properties_id || 0) == 0
    end
  end

  describe "sync_equipment_stats/1" do
    test "recomputes property bonuses once and removes them for broken or unequipped gear", %{
      state: state,
      property: property
    } do
      item = ItemStore.create(@entry, owner: state.guid, random_property: property)
      character = %{state.character | player: Inventory.equip(state.character.player, 15, item)}
      equipped = Character.sync_equipment_stats(character)
      assert equipped.unit.strength == 23
      assert equipped.unit.stamina == 25
      assert Character.sync_equipment_stats(equipped).unit.strength == 23

      ItemStore.put(%{item | item: %{item.item | durability: 0}})
      broken = Character.sync_equipment_stats(equipped)
      assert broken.unit.strength == 20
      assert broken.unit.stamina == 20

      ItemStore.put(item)
      repaired = Character.sync_equipment_stats(broken)
      assert repaired.unit.strength == 23
      unequipped = Character.sync_equipment_stats(%{repaired | player: %{repaired.player | mainhand: 0}})
      assert unequipped.unit.strength == 20
      assert unequipped.unit.stamina == 20
    end
  end

  defp build_inventory(_context) do
    property = %ItemProperty{id: @property_id, suffix: "of the Bear", enchantments: [@entry + 1, @entry + 2, 0]}
    other = %ItemProperty{id: @other_property_id, suffix: "of Strength", enchantments: [@entry + 1, 0, 0]}

    template = %ItemTemplate{
      entry: @entry,
      name: "Test Sword",
      random_property: @entry,
      inventory_type: 13,
      class: 2,
      max_durability: 50
    }

    rows = [
      {{:property, property.id}, property},
      {{:property, other.id}, other},
      {{:table, @entry}, [{property.id, 1.0}, {other.id, 1.0}]}
    ]

    :ets.insert(PropertyLoader, rows)
    :ets.insert(ItemLoader, {@entry, template})

    for {id, stat, amount} <- [{@entry + 1, 4, 3}, {@entry + 2, 7, 5}] do
      enchantment = %ItemEnchantment{id: id, effects: [%{type: 5, amount: amount, spell_id: stat}]}
      :ets.insert(EnchantmentLoader, {{:enchantment, id}, enchantment})
    end

    character =
      CharacterStore.create(%Character{
        id: 0,
        object: %Object{guid: 0},
        player: %Player{},
        unit: %Unit{
          health: 100,
          max_health: 100,
          base_health: 100,
          base_mana: 0,
          base_strength: 20,
          base_stamina: 20,
          level: 10,
          class: 1,
          race: 1
        },
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      })

    on_exit(fn ->
      Enum.each(rows, fn {key, _value} -> :ets.delete(PropertyLoader, key) end)
      :ets.delete(ItemLoader, @entry)
      :ets.delete(EnchantmentLoader, {:enchantment, @entry + 1})
      :ets.delete(EnchantmentLoader, {:enchantment, @entry + 2})
      :ets.delete(CharacterStore, character.id)

      :ets.select_delete(ItemStore, [
        {{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, character.object.guid}], [true]}
      ])
    end)

    %{state: %State{guid: character.object.guid, character: character}, property: property, template: template}
  end

  defp fill_inventory(state) do
    player =
      Enum.reduce(1..16, state.character.player, fn slot, player ->
        item = ItemStore.create(%ItemTemplate{entry: @entry + 10}, owner: state.guid)
        struct!(player, [{:"inv#{slot}", item.object.guid}])
      end)

    %{state | character: %{state.character | player: player}}
  end
end
