defmodule ThistleTea.Game.Entity.Logic.TargetSpellPowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.TargetSpellPower
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "benefit/3" do
    test "combines equipment, stacked auras, and school power by creature mask", %{caster: caster, target: target} do
      caster = %{
        caster
        | unit: %{
            caster.unit
            | equipment_bonuses: %{spell_shadow: 13, spell_fire: 7, spell_damage_versus: [{32, 48}]},
              auras: [holder(36, 20, 2), holder(4, 10)]
          }
      }

      spell = direct_spell()
      context = CastContext.from_caster(caster, spell, 2)
      assert TargetSpellPower.benefit(target, context, spell) == 101
      assert TargetSpellPower.benefit(with_type(target, 3), context, spell) == 63
      assert TargetSpellPower.benefit(with_type(target, 1), context, spell) == 13
      assert TargetSpellPower.benefit(target, context, %{spell | school: :fire}) == 95
      assert TargetSpellPower.benefit(target, context, %{spell | school: 2}) == 95
      assert caster.player.mod_damage_done_pos_shadow == nil
    end

    test "uses humanoid and shapeshifted player creature types", %{caster: caster} do
      spell = direct_spell()
      context = %{context(caster, spell) | spell_damage_versus: [{64, 30}, {1, 10}]}
      assert TargetSpellPower.benefit(caster, context, spell) == 30
      cat = %{caster | unit: %{caster.unit | shapeshift_form: 1}}
      assert TargetSpellPower.benefit(cat, context, spell) == 10
    end
  end

  describe "receive/4" do
    test "combines power before rounding and resolves each recipient independently", %{caster: caster, target: target} do
      spell = direct_spell()
      context = %{context(caster, spell) | spell_damage_bonus: %{shadow: 1}, spell_damage_versus: [{32, 49}]}
      {damaged, events} = SpellEffect.receive(target, context, spell, 0)
      assert damaged.unit.health == 875
      assert damage(events) == 125
      {other, events} = SpellEffect.receive(with_type(target, 1), context, spell, 0)
      assert other.unit.health == 900
      assert damage(events) == 100
    end

    test "scales the bonus with critical hits and skips fixed damage and healing", %{caster: caster, target: target} do
      spell = direct_spell()
      context = %{context(caster, spell) | spell_damage_versus: [{32, 100}], spell_crit_chance: 100}
      {damaged, events} = SpellEffect.receive(target, context, spell, 0)
      assert damaged.unit.health == 775
      assert damage(events) == 225
      assert Enum.any?(events, &match?(%Effects.SpellDamage{crit?: true}, &1))

      fixed = %{spell | custom_flags: 0x010}
      {_, events} = SpellEffect.receive(target, %{context | spell_crit_chance: 0}, fixed, 0)
      assert damage(events) == 100
      heal = %{spell | effects: [%{hd(spell.effects) | type: :heal}]}
      hurt = %{target | unit: %{target.unit | health: 500}}
      {healed, _events} = SpellEffect.receive(hurt, %{context | spell_crit_chance: 0}, heal, 0)
      assert healed.unit.health == 600
    end

    test "direct leech heals actual damage after overkill", %{caster: caster, target: target} do
      spell = direct_spell(:health_leech)
      context = %{context(caster, spell) | spell_damage_versus: [{32, 100}]}
      target = %{target | unit: %{target.unit | health: 120}}
      {dead, events} = SpellEffect.receive(target, context, spell, 0)
      assert dead.unit.health == 0
      assert damage(events) == 150
      assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 120}, &1))
    end
  end

  describe "tick/2" do
    test "periodic damage snapshots each recipient and survives caster removal", %{caster: caster, target: target} do
      spell = periodic_spell(:periodic_damage)
      buff = bonus_spell()
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, buff, 0)
      context = context(buffed, spell)
      {affected, _events} = SpellEffect.receive(target, context, spell, 0)
      assert hd(hd(affected.unit.auras).auras).amount == 125
      {unbuffed, _events} = Aura.remove_spells(buffed, [buff.id], 500)
      assert TargetSpellPower.snapshot(unbuffed) == []
      {ticked, events} = Aura.tick(affected, 1_000)
      assert ticked.unit.health == 875
      assert damage(events) == 125
      {other, _events} = SpellEffect.receive(with_type(target, 1), context, spell, 0)
      {other, events} = Aura.tick(other, 1_000)
      assert other.unit.health == 900
      assert damage(events) == 100
      {refreshed, _events} = SpellEffect.receive(ticked, context(unbuffed, spell), spell, 1_000)
      assert hd(hd(refreshed.unit.auras).auras).amount == 100
      {expired, _events} = Aura.tick(refreshed, 4_000)
      assert expired.unit.auras == []
    end

    test "periodic leech receives the bonus but periodic healing does not", %{caster: caster, target: target} do
      for {type, expected} <- [periodic_leech: 125, periodic_heal: 100] do
        spell = periodic_spell(type)
        context = %{context(caster, spell) | spell_damage_versus: [{32, 100}]}
        {affected, _events} = SpellEffect.receive(target, context, spell, 0)
        assert hd(hd(affected.unit.auras).auras).amount == expected
        {_, events} = Aura.tick(affected, 1_000)
        if type == :periodic_leech, do: assert(Enum.any?(events, &match?(%Effects.HealEntity{amount: 125}, &1)))
      end
    end
  end

  describe "apply_spell/5" do
    test "new casts reflect cancellation, expiry, and death while existing snapshots persist", %{
      caster: caster,
      target: target
    } do
      buff = bonus_spell()
      spell = direct_spell()
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, buff, 0)
      saved = context(buffed, spell)
      {cancelled, _events} = Aura.remove_spells(buffed, [buff.id], 500)
      {expired, _events} = Aura.tick(buffed, 1_000)
      dead = Core.take_damage(buffed, 1_000, 500)

      for entity <- [cancelled, expired, dead] do
        assert TargetSpellPower.benefit(target, context(entity, spell), spell) == 0
      end

      assert TargetSpellPower.benefit(target, saved, spell) == 100
    end
  end

  defp entities(_context) do
    unit = %Unit{health: 1_000, max_health: 1_000, level: 60, class: 9, auras: [], flags: 0x00040000}

    caster = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{object: %Object{guid: 2}, unit: unit, internal: %Internal{creature: %Creature{creature_type: 6}}}
    %{caster: caster, target: target}
  end

  defp holder(mask, amount, stacks \\ 1) do
    %Holder{
      spell: %Spell{id: 90_000},
      caster_guid: 1,
      stacks: stacks,
      auras: [%AuraData{type: :mod_flat_spell_damage_versus, amount: amount, misc_value: mask}]
    }
  end

  defp with_type(entity, type),
    do: %{entity | internal: %{entity.internal | creature: %{entity.internal.creature | creature_type: type}}}

  defp direct_spell(type \\ :school_damage) do
    %Spell{
      id: 90_001,
      school: :shadow,
      dmg_class: 1,
      effects: [%Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 0.5, multiple_value: 1.0}]
    }
  end

  defp periodic_spell(type) do
    %Spell{
      id: 90_002,
      school: :shadow,
      dmg_class: 1,
      duration_ms: 3_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: 100,
          bonus_coefficient: 0.25,
          amplitude_ms: 1_000,
          multiple_value: 1.0
        }
      ]
    }
  end

  defp bonus_spell do
    %Spell{
      id: 90_003,
      duration_ms: 1_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_flat_spell_damage_versus, base_points: 100, misc_value: 32}
      ]
    }
  end

  defp context(caster, spell),
    do: %{CastContext.from_caster(caster, spell, 2) | spell_crit_chance: 0, caster_position: nil}

  defp damage(events),
    do: Enum.find_value(events, fn event -> if match?(%Effects.SpellDamage{}, event), do: event.damage end)
end
