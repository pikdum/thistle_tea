defmodule ThistleTea.Game.Entity.Logic.DamageImmunityTest do
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
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "immune?/3" do
    test "matches school masks without relying on aura amounts", %{entity: entity} do
      entity = protect(entity, 5)
      assert DamageImmunity.immune?(entity, :physical)
      assert DamageImmunity.immune?(entity, :fire)
      refute DamageImmunity.immune?(entity, :frost)
      refute Aura.school_immune?(entity, :physical)
    end

    test "school bypass does not bypass damage immunity", %{entity: entity} do
      spell = %{damage_spell() | attributes: MapSet.new([:no_school_immunities])}
      school = protect(entity, 1, :school_immunity)
      refute DamageImmunity.immune?(school, :physical, spell)
      assert DamageImmunity.immune?(protect(entity), :physical, spell)
    end

    test "full bypass attributes permit damage through both immunity types", %{entity: entity} do
      for type <- [:school_immunity, :damage_immunity],
          attribute <- [:no_immunities, :ignore_caster_and_target_restrictions] do
        spell = %{damage_spell() | attributes: MapSet.new([attribute])}
        target = protect(entity, 1, type)
        refute DamageImmunity.immune?(target, :physical, spell)
        {updated, events} = SpellEffect.receive(target, 2, spell, 100)
        assert updated.unit.health == 80
        assert Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
      end
    end
  end

  describe "receive_attack/4" do
    test "immunity precedes avoidance and does not consume shields or trigger reactions", %{entity: entity} do
      holder = %Holder{
        spell: %Spell{id: 3},
        auras: [
          %AuraData{type: :school_absorb, amount: 50, misc_value: 1},
          %AuraData{type: :damage_shield, amount: 10}
        ]
      }

      entity = protect(entity)
      entity = %{entity | unit: %{entity.unit | auras: [holder | entity.unit.auras]}}
      attack = %{caster: 2, damage: 20, caster_level: 10}
      {updated, events} = Combat.receive_attack(entity, attack, 100, roll: 0)
      assert updated.unit.health == 100
      assert hd(updated.unit.auras) == holder

      assert Enum.any?(
               events,
               &match?(%Effects.AttackerStateUpdate{damage: 0, attack: %{damage_state: 7, absorb: 0}}, &1)
             )

      assert Enum.any?(events, &match?(%Effects.AttackOutcome{outcome: :immune, damage: 0}, &1))
      refute Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
    end

    test "unprotected schools still deal damage", %{entity: entity} do
      attack = %{caster: 2, damage: 20, spell_school_mask: 4, caster_level: 10}
      {updated, _events} = Combat.receive_attack(protect(entity), attack, 100, roll: 9_999)
      assert updated.unit.health == 80
    end
  end

  describe "receive/4" do
    test "hostile damage and control report immunity while healing still lands", %{entity: entity} do
      entity = protect(entity)

      for spell <- [damage_spell(), periodic_spell(:periodic_damage), control_spell()] do
        {updated, events} = SpellEffect.receive(entity, 2, spell, 100)
        assert updated == entity
        assert [%Effects.SpellLogMiss{reason: :immune}] = events
      end

      entity = %{entity | unit: %{entity.unit | health: 50}}
      heal = %{damage_spell() | effects: [%Effect{type: :heal, base_points: 20, implicit_target_a: :target_ally}]}
      {updated, _events} = SpellEffect.receive(entity, 2, heal, 100)
      assert updated.unit.health == 70
    end

    test "magic damage bypasses physical protection", %{entity: entity} do
      {updated, _events} = SpellEffect.receive(protect(entity), 2, %{damage_spell() | school: :fire}, 100)
      assert updated.unit.health < 100
    end
  end

  describe "tick/2" do
    test "existing damage, leech and mana drain pause without removing their holders", %{entity: entity} do
      for type <- [:periodic_damage, :periodic_leech, :periodic_mana_leech] do
        {target, _events} = Aura.apply_spell(entity, 2, 10, periodic_spell(type), 0)
        target = protect(target)
        {target, events} = Aura.tick(target, 500)
        assert target.unit.health == 100
        assert target.unit.power1 == 100
        assert [%Effects.SpellDamageImmune{source_guid: 2, target_guid: 1, spell_id: 2}] = events
        assert Aura.has_spell?(target, 2)

        {target, _events} = Aura.remove_spells(target, [1], 600)
        {target, events} = Aura.tick(target, 1_000)
        refute Enum.any?(events, &match?(%Effects.SpellDamageImmune{}, &1))

        if type == :periodic_mana_leech do
          assert target.unit.power1 == 80
          assert [%Effects.LeechPower{source_guid: 2, power_type: 0, amount: 20}] = events
        else
          assert target.unit.health == 80
        end
      end
    end

    test "periodic bypass attributes reach the damage core", %{entity: entity} do
      spell = %{periodic_spell(:periodic_damage) | attributes: MapSet.new([:no_immunities])}
      {entity, _events} = Aura.apply_spell(entity, 2, 10, spell, 0)
      {entity, events} = Aura.tick(protect(entity), 500)
      assert entity.unit.health == 80
      assert Enum.any?(events, &match?(%Effects.SpellDamage{}, &1))
    end
  end

  describe "aura lifecycle" do
    test "overlapping sources remain until the last expires", %{entity: entity} do
      entity = protect(entity)
      {entity, _events} = Aura.apply_spell(entity, 3, 10, %{protection(1, :damage_immunity) | id: 4}, 0)
      {entity, _events} = Aura.remove_spells(entity, [1], 100)
      assert DamageImmunity.immune?(entity, :physical)
      {entity, _events} = Aura.expire_due(entity, 1_000)
      refute DamageImmunity.immune?(entity, :physical)
      assert Core.take_damage(entity, 20, 1_001).unit.health == 80
    end

    test "cancellation restores damage and death clears temporary protection", %{entity: entity} do
      {cancelled, _events} = Aura.cancel_spell(protect(entity), 1, 100)
      refute DamageImmunity.immune?(cancelled, :physical)
      dead = Core.take_damage(protect(entity), 100, 100, school: :fire)
      assert dead.unit.health == 0
      refute DamageImmunity.immune?(dead, :physical)
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, power_type: 0, power1: 100, max_power1: 100, level: 10, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp protect(entity, mask \\ 1, type \\ :damage_immunity) do
    {entity, _events} = Aura.apply_spell(entity, 1, 10, protection(mask, type), 0)
    entity
  end

  defp protection(mask, type) do
    %Spell{
      id: 1,
      duration_ms: 1_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, misc_value: mask, implicit_target_a: :caster}]
    }
  end

  defp damage_spell do
    %Spell{id: 2, school: :physical, effects: [%Effect{type: :school_damage, base_points: 20}]}
  end

  defp periodic_spell(type) do
    %Spell{
      id: 2,
      school: :physical,
      duration_ms: 5_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: 20,
          amplitude_ms: 500,
          misc_value: 0,
          implicit_target_a: :target_enemy
        }
      ]
    }
  end

  defp control_spell do
    %{
      periodic_spell(:mod_stun)
      | effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]
    }
  end
end
