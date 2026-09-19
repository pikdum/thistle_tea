defmodule ThistleTea.Game.World.Loader.TargetDamageDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "slayer spells load amounts and creature masks" do
      for {id, type, amount} <- [{7784, 1, 2}, {13_650, 1, 6}, {13_651, 4, 6}, {4719, 6, 13}, {4646, 3, 8}] do
        spell = SpellLoader.load(id)
        caster = %Mob{unit: %Unit{health: 100, max_health: 100, auras: []}}
        {caster, _events} = Aura.apply_spell(caster, 1, 60, spell, 0)
        snapshot = TargetDamage.snapshot(caster)

        for target_type <- 1..9 do
          target = %{caster | internal: %Internal{creature: %Creature{creature_type: target_type}}}
          assert TargetDamage.bonus(target, snapshot) == if(target_type == type, do: amount, else: 0)
        end
      end
    end

    test "on-equip slaying damage stays separate from displayed damage and spell power" do
      template = %ItemTemplate{entry: 998_611, spellid_1: 7594, spelltrigger_1: 1}
      bonuses = EquipmentStats.bonuses([template], &SpellLoader.load/1)
      assert bonuses.damage_done_creature == [{1, 10}]
      assert bonuses.spell_physical == 0
      assert bonuses.spell_fire == 0
      assert bonuses.mainhand_damage == 0
      assert bonuses.healing == 0
    end
  end

  describe "sync_equipment_stats/1" do
    setup [:enchanted_weapons]

    test "stacks independent weapon enchants and reconciles removal, breakage, and restoration", %{
      character: character,
      mainhand: mainhand,
      offhand: offhand
    } do
      equipped = Character.sync_equipment_stats(character)
      assert Enum.sort(TargetDamage.snapshot(equipped)) == [{1, 6}, {1, 6}]
      assert equipped.unit.min_damage == 100
      assert equipped.unit.min_offhand_damage == 100
      assert Character.sync_equipment_stats(equipped) == equipped

      bagged = %{equipped | player: %{equipped.player | offhand: nil, inv1: offhand.object.guid}}
      assert TargetDamage.snapshot(Character.sync_equipment_stats(bagged)) == [{1, 6}]

      ItemStore.put(%{mainhand | item: %{mainhand.item | durability: 0}})
      broken = Character.sync_equipment_stats(equipped)
      assert TargetDamage.snapshot(broken) == [{1, 6}]
      assert broken.player.broken_equipment == [:mainhand]
      ItemStore.put(mainhand)
      assert length(TargetDamage.snapshot(Character.sync_equipment_stats(broken))) == 2

      ItemStore.put(Item.put_permanent_enchantment(mainhand, 854))
      replaced = Character.sync_equipment_stats(equipped)
      assert Enum.sort(TargetDamage.snapshot(replaced)) == [{1, 6}, {8, 6}]
      assert Enum.sort(TargetDamage.snapshot(Enchantments.restore(replaced))) == [{1, 6}, {8, 6}]
      dead = Core.take_damage(replaced, 1_000, 100)
      assert Enum.sort(TargetDamage.snapshot(dead)) == [{1, 6}, {8, 6}]
    end
  end

  defp enchanted_weapons(_context) do
    for id <- [853, 854] do
      row = DBC.get(SpellItemEnchantment, id)
      assert row.enchantment_type_0 == 3
      enchantment = %ItemEnchantment{id: id, effects: [%{type: 3, spell_id: row.effect_arg_0}]}
      previous = :ets.lookup(EnchantmentLoader, {:enchantment, id})
      :ets.insert(EnchantmentLoader, {{:enchantment, id}, enchantment})

      on_exit(fn ->
        :ets.delete(EnchantmentLoader, {:enchantment, id})
        :ets.insert(EnchantmentLoader, previous)
      end)
    end

    template = %ItemTemplate{
      entry: 998_612,
      class: 2,
      subclass: 7,
      inventory_type: 13,
      delay: 2_000,
      dmg_min1: 100,
      dmg_max1: 100,
      max_durability: 50
    }

    :ets.insert(ItemLoader, {template.entry, template})
    mainhand = template |> ItemStore.create() |> Item.put_permanent_enchantment(853) |> ItemStore.put()
    offhand = template |> ItemStore.create() |> Item.put_permanent_enchantment(853) |> ItemStore.put()

    on_exit(fn ->
      ItemStore.delete(mainhand.object.guid)
      ItemStore.delete(offhand.object.guid)
      :ets.delete(ItemLoader, template.entry)
    end)

    player =
      %Player{mainhand: mainhand.object.guid, offhand: offhand.object.guid}
      |> Inventory.sync_visible_item(15, mainhand)
      |> Inventory.sync_visible_item(16, offhand)

    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, class: 1, health: 100, max_health: 100, base_health: 100, auras: []},
      player: player,
      internal: %Internal{},
      movement_block: %MovementBlock{}
    }

    %{character: character, mainhand: mainhand, offhand: offhand}
  end
end
