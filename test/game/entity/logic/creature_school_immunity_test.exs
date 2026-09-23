defmodule ThistleTea.Game.Entity.Logic.CreatureSchoolImmunityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureImmunity
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:creature]

  describe "receive/4" do
    test "template schools block both direct damage and hostile auras", %{target: target, fire: fire} do
      for auras <- [[], nil],
          target = %{target | unit: %{target.unit | auras: auras}},
          spell <- [
            fire,
            %{fire | effects: [%Effect{type: :apply_aura, aura: :mod_stun, implicit_target_a: :target_enemy}]}
          ] do
        assert {^target, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.receive(target, caster(), spell, 1_000)
        assert {^target, []} = Aura.apply_spell(target, 2, 50, spell, 1_000)
      end
    end

    test "other schools and friendly effects still land", %{target: target, fire: fire} do
      {damaged, _events} = SpellEffect.receive(target, caster(), %{fire | school: :frost}, 1_000)
      assert damaged.unit.health == 80
      heal = %{fire | effects: [%Effect{type: :heal, base_points: 10, implicit_target_a: :target_ally}]}
      {healed, _events} = SpellEffect.receive(damaged, caster(), heal, 1_001)
      assert healed.unit.health == 90

      buff = %{
        fire
        | effects: [%Effect{type: :apply_aura, aura: :mod_increase_speed, base_points: 10, implicit_target_a: :caster}]
      }

      {buffed, _events} = Aura.apply_spell(target, 1, 50, buff, 1_000)
      assert Aura.has_spell?(buffed, fire.id)
    end

    test "full bypass attributes permit damage but the aura-only bypass does not", %{target: target, fire: fire} do
      for attribute <- [:no_immunities, :ignore_caster_and_target_restrictions] do
        spell = %{fire | attributes: MapSet.new([attribute])}
        refute DamageImmunity.immune?(target, :fire, spell)
        {damaged, _events} = SpellEffect.receive(target, caster(), spell, 1_000)
        assert damaged.unit.health == 80
      end

      spell = %{fire | attributes: MapSet.new([:no_school_immunities])}
      assert DamageImmunity.immune?(target, :fire, spell)
      assert {^target, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.receive(target, caster(), spell, 1_000)
    end
  end

  describe "tick/2" do
    test "periodic protection retains tick clocks and resumes after protection changes", %{target: target, fire: fire} do
      unprotected = %{target | internal: %{target.internal | creature: %Creature{school_immune_mask: 0}}}

      dot = %{
        fire
        | effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 20, amplitude_ms: 1_000}]
      }

      {unprotected, _events} = Aura.apply_spell(unprotected, 2, 50, dot, 0)
      protected = %{unprotected | internal: target.internal}
      {protected, events} = Aura.tick(protected, 1_000)
      assert protected.unit.health == 100
      assert [%Effects.SpellDamageImmune{spell_id: 99}] = events
      assert Aura.has_spell?(protected, 99)
      cleared = %{protected | internal: unprotected.internal}
      {damaged, _events} = Aura.tick(cleared, 2_000)
      assert damaged.unit.health == 80
    end
  end

  describe "school?/2" do
    test "matches each bit in a combined mask", %{target: target} do
      target = %{target | internal: %{target.internal | creature: %Creature{school_immune_mask: 21}}}
      for school <- [:physical, :fire, :frost], do: assert(CreatureImmunity.school?(target, school))
      for school <- [:holy, :nature, :shadow, :arcane], do: refute(CreatureImmunity.school?(target, school))
    end
  end

  defp caster, do: %CastContext{caster_guid: 2, caster_level: 50}

  defp creature(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 50, auras: []},
        internal: %Internal{creature: %Creature{school_immune_mask: 4}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      },
      fire: %Spell{id: 99, school: :fire, duration_ms: 5_000, effects: [%Effect{type: :school_damage, base_points: 20}]}
    }
  end
end
