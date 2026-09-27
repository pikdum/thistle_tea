defmodule ThistleTea.Game.Entity.Logic.MechanicalHealingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:repair]

  describe "receive/4" do
    test "repairs without critical healing, healing procs, or assist threat", context do
      %{target: target, spell: spell, cast: cast} = context
      {target, events} = SpellEffect.receive(target, %{cast | spell_crit_chance: 100}, spell, 0)

      assert target.unit.health == 800
      assert [%Effects.SpellHeal{damage: 700, crit?: false, proc_type: nil}] = events
      assert Spell.healing?(spell)
    end

    test "applies caster and current recipient healing bonuses", context do
      %{target: target, spell: spell, cast: cast} = context

      modifier = %Holder{
        spell: %Spell{id: 2},
        auras: [
          %AuraData{type: :mod_healing, amount: 100, misc_value: 1},
          %AuraData{type: :mod_healing_pct, amount: -50}
        ]
      }

      target = %{target | unit: %{target.unit | auras: [modifier]}}
      spell = %{spell | effects: [%{hd(spell.effects) | bonus_coefficient: 0.5}]}
      cast = %{cast | healing_bonus: 200, healing_done_multiplier: 1.5}
      {target, [%Effects.SpellHeal{damage: 625}]} = SpellEffect.receive(target, cast, spell, 0)
      assert target.unit.health == 725
    end

    test "caps health while reporting the full repair amount", context do
      %{target: target, spell: spell, cast: cast} = context
      target = %{target | unit: %{target.unit | health: 900}}
      {target, [%Effects.SpellHeal{damage: 700}]} = SpellEffect.receive(target, cast, spell, 0)
      assert target.unit.health == 1_000
    end

    test "does not repair a corpse", context do
      %{target: target, spell: spell, cast: cast} = context
      target = %{target | unit: %{target.unit | health: 0}}
      assert {^target, []} = SpellEffect.receive(target, cast, spell, 0)
    end

    test "honors effect immunity and its removal", context do
      %{target: target, spell: spell, cast: cast} = context

      immunity = %Spell{
        id: 3,
        duration_ms: 1_000,
        attributes: MapSet.new([:immunity_to_hostile_and_friendly_effects]),
        effects: [%Effect{index: 0, type: :apply_aura, aura: :effect_immunity, misc_value: :heal_mechanical}]
      }

      {target, _} = Aura.apply_spell(target, 1, 60, immunity, 0)
      {blocked, events} = SpellEffect.receive(target, cast, spell, 0)
      assert blocked.unit.health == 100
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
      {target, _} = Aura.remove_spells(target, [3], 100)
      {target, [%Effects.SpellHeal{}]} = SpellEffect.receive(target, cast, spell, 100)
      assert target.unit.health == 800
    end
  end

  describe "validate_target/4" do
    test "requires a living friendly mechanical target", %{target: caster, spell: spell} do
      target = %{guid: 2, alive?: true, hostile?: false, creature_type: 9, level: 60, distance: 5.0}
      assert :ok = CastValidation.validate_target(caster, spell, Target.unit(2), target)

      for invalid <- [%{target | creature_type: 7}, %{target | hostile?: true}, %{target | alive?: false}] do
        assert {:error, _} = CastValidation.validate_target(caster, spell, Target.unit(2), invalid)
      end
    end
  end

  defp repair(_context) do
    target = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 1_000, level: 60, auras: []},
      internal: %Internal{creature: %Creature{creature_type: 9}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 15_057,
      school: :physical,
      dmg_class: 1,
      spell_level: 30,
      target_creature_type_mask: 256,
      effects: [
        %Effect{
          index: 0,
          type: :heal_mechanical,
          base_points: 700,
          bonus_coefficient: 0.0,
          implicit_target_a: :target_ally
        }
      ]
    }

    %{target: target, spell: spell, cast: %CastContext{caster_guid: 2, caster_level: 60}}
  end
end
