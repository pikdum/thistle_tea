defmodule ThistleTea.Game.Entity.Logic.ManaShieldTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "absorb_damage/4" do
    test "unmatched schools leave mana and shield untouched", %{entity: entity} do
      for school <- [:holy, :fire, :nature, :frost, :shadow, :arcane] do
        assert {^entity, 50} = Aura.absorb_damage(entity, 50, school, 100)
      end
    end

    test "uses the effect's school mask and mana conversion", %{entity: entity} do
      entity = change_shield(entity, %{misc_value: 4, multiple_value: 3.0})
      {updated, 0} = Aura.absorb_damage(entity, 20, :fire, 100)
      assert updated.unit.power1 == 140
      assert shield_amount(updated) == 100
      assert {^entity, 20} = Aura.absorb_damage(entity, 20, :physical, 100)
    end

    test "both talent ranks reduce mana spent", %{entity: entity} do
      for {percent, mana} <- [{-10, 146}, {-20, 152}] do
        {updated, 0} = entity |> talent(percent) |> Aura.absorb_damage(30, :physical, 100)
        assert updated.unit.power1 == mana
        assert shield_amount(updated) == 90
      end
    end

    test "current talents affect shields that are already active", %{entity: entity} do
      {entity, 0} = entity |> talent(-20) |> Aura.absorb_damage(30, :physical, 100)
      {entity, _events} = Aura.remove_spells(entity, [12_605], 101)
      {entity, 0} = Aura.absorb_damage(entity, 30, :physical, 102)
      assert entity.unit.power1 == 92
      assert shield_amount(entity) == 60
    end

    test "ignores unrelated spell families and masks", %{entity: entity} do
      for {family, mask} <- [{8, 0x8000}, {3, 1}, {3, 0}] do
        {updated, 0} = entity |> talent(-20, family, mask) |> Aura.absorb_damage(30, :physical, 100)
        assert updated.unit.power1 == 140
      end
    end

    test "mana limits absorption without exhausting the shield", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 16}}
      {entity, 20} = entity |> talent(-20) |> Aura.absorb_damage(30, :physical, 100)
      assert entity.unit.power1 == 0
      assert shield_amount(entity) == 110
      assert {^entity, 30} = Aura.absorb_damage(entity, 30, :physical, 101)
      entity = %{entity | unit: %{entity.unit | power1: 16}}
      {entity, 20} = Aura.absorb_damage(entity, 30, :physical, 102)
      assert shield_amount(entity) == 100
    end

    test "fractional conversion never overspends the available mana", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 17}}
      {entity, 20} = entity |> talent(-20) |> Aura.absorb_damage(30, :physical, 100)
      assert entity.unit.power1 == 1
      assert shield_amount(entity) == 110
      assert {^entity, 1} = Aura.absorb_damage(entity, 1, :physical, 101)
    end

    test "zero conversion permits absorption without mana", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 0}}

      for protected <- [change_shield(entity, %{multiple_value: 0.0}), talent(entity, -100)] do
        {updated, 0} = Aura.absorb_damage(protected, 30, :physical, 100)
        assert updated.unit.power1 == 0
        assert shield_amount(updated) == 90
      end
    end

    test "ordinary absorbs precede mana shields in either application order", %{entity: entity} do
      [mana_shield] = entity.unit.auras

      barrier = %Holder{
        spell: %Spell{id: 11_426},
        auras: [%AuraData{type: :school_absorb, amount: 50, misc_value: 127}]
      }

      for holders <- [[mana_shield, barrier], [barrier, mana_shield]] do
        protected = %{entity | unit: %{entity.unit | auras: holders}}
        {updated, 0} = Aura.absorb_damage(protected, 70, :physical, 100)
        assert updated.unit.power1 == 160
        assert shield_amount(updated) == 100
        assert length(updated.unit.auras) == 1
      end
    end

    test "ordinary absorbs can protect a player with no mana", %{entity: entity} do
      barrier = %Holder{
        spell: %Spell{id: 11_426},
        auras: [%AuraData{type: :school_absorb, amount: 50, misc_value: 127}]
      }

      entity = %{entity | unit: %{entity.unit | power1: 0, auras: entity.unit.auras ++ [barrier]}}
      {updated, 20} = Aura.absorb_damage(entity, 70, :physical, 100)
      assert updated.unit.power1 == 0
      assert shield_amount(updated) == 120
    end

    test "exhaustion removes the shield and publishes the change", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 300}}
      {updated, 30} = Aura.absorb_damage(entity, 150, :physical, 100)
      assert updated.unit.auras == []
      assert updated.unit.power1 == 60
      assert updated.internal.broadcast_update?
    end
  end

  describe "receive_attack/4" do
    test "combat reports absorbed physical damage and drains mana", %{entity: entity} do
      attack = %{caster: 2, damage: 30, caster_level: 10}
      {entity, events} = Combat.receive_attack(entity, attack, 100, roll: 9_999)
      assert entity.unit.health == 500
      assert entity.unit.power1 == 140
      assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: 0, attack: %{absorb: 30}}, &1))
    end

    test "partial absorption reports only damage reaching health", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 20}}
      attack = %{caster: 2, damage: 30, caster_level: 10}
      {entity, events} = Combat.receive_attack(entity, attack, 100, roll: 9_999)
      assert entity.unit.health == 480
      assert entity.unit.power1 == 0
      assert Enum.any?(events, &match?(%Effects.AttackerStateUpdate{damage: 20, attack: %{absorb: 10}}, &1))
    end
  end

  describe "receive/4" do
    test "magical damage reaches health without consuming a physical shield", %{entity: entity} do
      spell = %Spell{id: 133, school: :fire, effects: [%Effect{index: 0, type: :school_damage, base_points: 30}]}
      context = %CastContext{caster_guid: 2, caster_level: 10}
      {updated, events} = SpellEffect.receive(entity, context, spell, 100)
      assert updated.unit.health == 470
      assert updated.unit.power1 == 200
      assert shield_amount(updated) == 120
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 30, absorbed: 0}, &1))
    end
  end

  describe "take_damage_with_absorb/4" do
    test "overflow damage reaches health", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | power1: 20}}
      {entity, 10} = Core.take_damage_with_absorb(entity, 30, 100, school: :physical)
      assert entity.unit.health == 480
      assert entity.unit.power1 == 0
    end
  end

  defp entity(_context) do
    spell = %Spell{id: 1463, spell_family: 3, family_flags_0: 0x8000}

    holder = %Holder{
      spell: spell,
      auras: [%AuraData{type: :mana_shield, amount: 120, misc_value: 1, multiple_value: 2.0}]
    }

    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 10, health: 500, max_health: 500, power1: 200, max_power1: 300, auras: [holder]},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{entity: entity}
  end

  defp change_shield(entity, changes) do
    [holder] = entity.unit.auras
    [aura] = holder.auras
    holder = %{holder | auras: [struct!(aura, changes)]}
    %{entity | unit: %{entity.unit | auras: [holder]}}
  end

  defp shield_amount(entity) do
    [%{amount: amount}] = Aura.auras_of_type(entity, :mana_shield)
    amount
  end

  defp talent(entity, amount, family \\ 3, mask \\ 0x8000) do
    holder = %Holder{
      spell: %Spell{id: 12_605, spell_family: family},
      auras: [%AuraData{type: :add_pct_modifier, amount: amount, misc_value: 27, class_mask: mask}]
    }

    %{entity | unit: %{entity.unit | auras: entity.unit.auras ++ [holder]}}
  end
end
