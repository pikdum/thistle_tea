defmodule ThistleTea.Game.Entity.Logic.AbsorbScalingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "apply_spell/4" do
    test "Power Word: Shield uses caster healing after base modifiers", %{caster: caster, target: target} do
      spell = shield()
      context = CastContext.from_caster(caster, spell, target.object.guid)
      modifier = %AuraData{type: :add_pct_modifier, misc_value: 8, amount: 15}
      context = %{context | spell_modifiers: [modifier], effect_healing_multiplier: 2.0}
      {shielded, _events} = Aura.apply_spell(target, context, spell, 0)
      assert capacity(shielded) == 215
      assert shielded.unit.health == target.unit.health

      low_rank = %{spell | spell_level: 6}
      {shielded, _events} = Aura.apply_spell(target, context, low_rank, 0)
      assert capacity(shielded) == 162
    end

    test "wards use their casting school and accept generic-family Shadow Ward", %{caster: caster, target: target} do
      for {school, family, flags, mask, expected} <- [
            {:fire, 3, 8, 4, 120},
            {:frost, 3, 256, 16, 130},
            {:shadow, 0, 0, 32, 140},
            {:shadow, 5, 0, 32, 140}
          ] do
        spell = %{
          shield()
          | school: school,
            spell_family: family,
            family_flags_0: flags,
            spell_icon: 207,
            category: 56,
            effects: [%{hd(shield().effects) | misc_value: mask}]
        }

        context = CastContext.from_caster(caster, spell, target.object.guid)
        {shielded, _events} = Aura.apply_spell(target, context, spell, 0)
        assert capacity(shielded) == expected
        {unchanged, unabsorbed} = Aura.absorb_damage(shielded, 50, :physical, 1)
        assert unabsorbed == 50
        assert capacity(unchanged) == expected
        {depleted, remaining} = Aura.absorb_damage(shielded, expected + 1, school, 2)
        assert remaining == 1
        assert depleted.unit.auras == []
      end
    end

    test "Mana Shield and unrelated absorbs receive no power bonus", %{caster: caster, target: target} do
      mana_shield = %{
        shield()
        | spell_family: 3,
          family_flags_0: 0x8000,
          school: :arcane,
          effects: [%{hd(shield().effects) | aura: :mana_shield, multiple_value: 2.0, misc_value: 1}]
      }

      for spell <- [mana_shield, %{shield() | spell_family: 0}, %{shield() | family_flags_0: 2}] do
        context = CastContext.from_caster(caster, spell, target.object.guid)
        {shielded, _events} = Aura.apply_spell(target, context, spell, 0)
        assert capacity(shielded) == 100
      end

      context = CastContext.from_caster(caster, mana_shield, target.object.guid)
      {shielded, _events} = Aura.apply_spell(target, context, mana_shield, 0)
      {depleted, remaining} = Aura.absorb_damage(shielded, 120, :physical, 1)
      assert remaining == 20
      assert depleted.unit.power1 == 800
      assert depleted.unit.auras == []
    end

    test "caster buffs enter the snapshot and cannot replenish a consumed shield", %{caster: caster, target: target} do
      buff = %Spell{
        id: 900_050,
        duration_ms: 1_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_healing_done, base_points: 500, misc_value: 2}]
      }

      spell = shield()
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, buff, 0)
      context = CastContext.from_caster(buffed, spell, target.object.guid)
      {shielded, _events} = Aura.apply_spell(target, context, spell, 0)
      assert capacity(shielded) == 250
      {used, remaining} = Aura.absorb_damage(shielded, 225, :shadow, 500)
      assert remaining == 0
      assert capacity(used) == 25
      {synchronized, _events} = Aura.apply_spell(used, 1, 60, buff, 600)
      assert capacity(synchronized) == 25
      {expired_buff, _events} = Aura.tick(buffed, 1_001)
      fresh = CastContext.from_caster(expired_buff, spell, target.object.guid)
      {refreshed, _events} = Aura.apply_spell(used, fresh, spell, 1_001)
      assert capacity(refreshed) == 200
      {depleted, remaining} = Aura.absorb_damage(refreshed, 201, :shadow, 1_002)
      assert remaining == 1
      assert depleted.unit.auras == []
    end

    test "expiry, cancellation, and death remove the scaled shield", %{caster: caster, target: target} do
      spell = shield()
      context = CastContext.from_caster(caster, spell, target.object.guid)
      {shielded, _events} = Aura.apply_spell(target, context, spell, 0)
      {expired, _events} = Aura.tick(shielded, 30_001)
      {cancelled, _events} = Aura.cancel_spell(shielded, spell.id, 1_000)
      dead = Core.take_damage(shielded, 1_000, 1_000, environmental?: true)

      for entity <- [expired, cancelled, dead] do
        refute Aura.has_spell?(entity, spell.id)
      end
    end
  end

  defp capacity(entity) do
    for holder <- entity.unit.auras,
        aura <- holder.auras,
        aura.type in [:school_absorb, :mana_shield],
        reduce: 0 do
      total -> total + aura.amount
    end
  end

  defp shield do
    %Spell{
      id: 900_049,
      spell_family: 6,
      family_flags_0: 1,
      school: :holy,
      spell_level: 60,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :school_absorb, base_points: 100, misc_value: 127}]
    }
  end

  defp entities(_context) do
    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        level: 60,
        class: 5,
        health: 1_000,
        max_health: 1_000,
        power1: 1_000,
        max_power1: 1_000,
        equipment_bonuses: %{healing: 1_000, spell_fire: 200, spell_frost: 300, spell_shadow: 400, spell_arcane: 500},
        auras: []
      },
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %{
      caster
      | object: %Object{guid: 2},
        unit: %{caster.unit | equipment_bonuses: %{healing: 9_000, spell_holy: 9_000}}
    }

    %{caster: caster, target: target}
  end
end
