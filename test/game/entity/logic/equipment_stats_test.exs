defmodule ThistleTea.Game.Entity.Logic.EquipmentStatsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_character]

  defp build_character(_context) do
    character = %{
      unit: %Unit{
        class: 1,
        race: 1,
        level: 10,
        strength: 30,
        agility: 21,
        stamina: 25,
        intellect: 20,
        spirit: 21,
        base_strength: 30,
        base_agility: 21,
        base_stamina: 25,
        base_intellect: 20,
        base_spirit: 21,
        base_health: 100,
        base_mana: 0,
        health: 170,
        max_health: 170
      },
      player: %Player{},
      internal: %Internal{}
    }

    chest =
      Item.build(
        %ItemTemplate{
          entry: 100,
          inventory_type: 5,
          armor: 120,
          fire_res: 10,
          stat_type1: 7,
          stat_value1: 5,
          stat_type2: 4,
          stat_value2: 3
        },
        0x4000_0000_0000_0001,
        owner: 1
      )

    {:ok, character: character, chest: chest}
  end

  defp get_item_fn(items) do
    by_guid = Map.new(items, fn item -> {item.object.guid, item} end)
    fn guid -> Map.get(by_guid, guid) end
  end

  describe "bonuses/1" do
    test "sums stats, armor, and resistances across templates", %{chest: chest} do
      template = Item.template(chest)

      bonuses = EquipmentStats.bonuses([template, template])

      assert bonuses.armor == 240
      assert bonuses.fire == 20
      assert bonuses.stamina == 10
      assert bonuses.strength == 6
      assert bonuses.agility == 0
    end

    test "derives quiver haste from its on-equip DBC spell" do
      quiver = %ItemTemplate{
        entry: 18_714,
        class: 11,
        subclass: 2,
        inventory_type: 18,
        spellid_1: 29_414,
        spelltrigger_1: 1
      }

      get_spell = fn 29_414 ->
        %Spell{effects: [%Effect{type: :apply_aura, aura: :mod_ranged_haste, base_points: 14}]}
      end

      assert EquipmentStats.bonuses([quiver], get_spell).ranged_haste == 14
    end
  end

  describe "resync/2" do
    test "applies bonuses from equipped items", %{character: character, chest: chest} do
      player = Inventory.equip(character.player, :chest, chest)
      character = EquipmentStats.resync(%{character | player: player}, get_item_fn([chest]))

      assert character.unit.strength == 33
      assert character.unit.stamina == 30
      assert character.unit.normal_resistance == 120
      assert character.unit.fire_resistance == 10
      assert character.unit.max_health == 100 + 20 + (30 - 20) * 10
      assert character.unit.health == 170
    end

    test "is idempotent", %{character: character, chest: chest} do
      player = Inventory.equip(character.player, :chest, chest)
      get_item = get_item_fn([chest])

      once = EquipmentStats.resync(%{character | player: player}, get_item)
      twice = EquipmentStats.resync(once, get_item)

      assert once.unit == twice.unit
    end

    test "removes bonuses on unequip and clamps health", %{character: character, chest: chest} do
      player = Inventory.equip(character.player, :chest, chest)
      get_item = get_item_fn([chest])

      equipped = EquipmentStats.resync(%{character | player: player}, get_item)
      equipped = %{equipped | unit: %{equipped.unit | health: equipped.unit.max_health}}

      unequipped = EquipmentStats.resync(%{equipped | player: %Player{}}, get_item)

      assert unequipped.unit.strength == 30
      assert unequipped.unit.stamina == 25
      assert unequipped.unit.normal_resistance == 0
      assert unequipped.unit.max_health == 170
      assert unequipped.unit.health == 170
    end

    test "applies direct health and mana bonuses", %{character: character} do
      trinket =
        Item.build(
          %ItemTemplate{entry: 200, inventory_type: 12, stat_type1: 1, stat_value1: 50, stat_type2: 0, stat_value2: 30},
          0x4000_0000_0000_0002,
          owner: 1
        )

      character = %{character | unit: %{character.unit | base_mana: 200, power1: 230, max_power1: 230}}
      player = Inventory.equip(character.player, :trinket1, trinket)
      character = EquipmentStats.resync(%{character | player: player}, get_item_fn([trinket]))

      assert character.unit.max_health == 170 + 50
      assert character.unit.max_power1 == 200 + 20 + 30
    end

    test "collects spell power from on-equip spells", %{character: character} do
      robe =
        Item.build(
          %ItemTemplate{entry: 300, inventory_type: 20, spellid_1: 9000, spelltrigger_1: 1},
          0x4000_0000_0000_0003,
          owner: 1
        )

      equip_spell = %Spell{
        id: 9000,
        name: "Increase Spell Dam",
        school: :physical,
        cast_time_ms: 0,
        duration_ms: -1,
        mana_cost: 0,
        gcd_ms: 0,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_damage_done, base_points: 20, misc_value: 126},
          %Effect{index: 1, type: :apply_aura, aura: :mod_healing_done, base_points: 32},
          %Effect{index: 2, type: :apply_aura, aura: :mod_attack_power, base_points: 9}
        ]
      }

      get_spell = fn 9000 -> equip_spell end

      player = Inventory.equip(character.player, :chest, robe)
      character = EquipmentStats.resync(%{character | player: player}, get_item_fn([robe]), get_spell)

      bonuses = character.unit.equipment_bonuses
      assert bonuses.spell_fire == 20
      assert bonuses.spell_shadow == 20
      assert bonuses.spell_physical == 0
      assert bonuses.healing == 32
      assert bonuses.attack_power == 9
      assert character.player.mod_damage_done_pos_fire == 20
      assert character.player.mod_damage_done_pos_physical == 0
    end

    test "base stat changes after resync keep gear bonuses", %{character: character, chest: chest} do
      player = Inventory.equip(character.player, :chest, chest)
      get_item = get_item_fn([chest])

      equipped = EquipmentStats.resync(%{character | player: player}, get_item)
      assert equipped.unit.equipment_bonuses.armor == 120

      leveled = %{equipped | unit: %{equipped.unit | base_stamina: 40, base_health: 200}}
      resynced = EquipmentStats.resync(leveled, get_item)

      assert resynced.unit.stamina == 45
      assert resynced.unit.normal_resistance == 120
      assert resynced.unit.max_health == 200 + 20 + (45 - 20) * 10
    end
  end
end
