defmodule ThistleTea.Game.Entity.Logic.SpellEffectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  defp target_fixture do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 20, max_health: 20, level: 1, auras: []},
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  describe "receive/4" do
    test "lethal damage prevents later aura effects from being applied" do
      spell = %Spell{
        id: 133,
        name: "Fireball",
        school: :fire,
        duration_ms: 8_000,
        effects: [
          %Effect{index: 0, type: :school_damage, base_points: 50, die_sides: 0},
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: 5,
            die_sides: 0,
            aura: :periodic_damage,
            amplitude_ms: 2_000
          }
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}

      {target, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert target.unit.health == 0
      assert target.unit.auras == []

      assert [%{type: :spell_damage, damage: 50, source_guid: 999, target_guid: 1, periodic?: false}] =
               events
    end

    test "periodic trigger spell auras fire the triggered spell instead of applying an aura" do
      spell = %Spell{
        id: 5143,
        name: "Arcane Missiles",
        school: :arcane,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            trigger_spell_id: 7268,
            amplitude_ms: 1_000
          }
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}

      {target, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert target.unit.auras == []

      assert [%{type: :trigger_spell, source_guid: 999, target_guid: 1, spell_id: 7268}] = events
    end

    test "persistent periodic area damage applies as spell damage for channel ticks" do
      spell = %Spell{
        id: 10,
        name: "Blizzard",
        school: :frost,
        effects: [
          %Effect{
            index: 0,
            type: :persistent_area_aura,
            aura: :periodic_damage,
            base_points: 24,
            die_sides: 0
          }
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}

      {target, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert target.unit.health == 0
      assert [%{type: :spell_damage, damage: 24, periodic?: true, spell_id: 10}] = events
    end

    test "heal effects restore health without emitting damage events" do
      spell = %Spell{
        id: 2050,
        name: "Lesser Heal",
        school: :holy,
        effects: [
          %Effect{
            index: 0,
            type: :heal,
            base_points: 15,
            die_sides: 0
          }
        ]
      }

      target = %{target_fixture() | unit: %Unit{health: 10, max_health: 20, level: 1, auras: []}}
      context = %CastContext{caster_guid: 999, caster_level: 10}

      {target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.unit.health == 20
      assert target.internal.broadcast_update? == true
      assert events == []
    end

    test "trigger spell effects return trigger events" do
      spell = %Spell{
        id: 168,
        name: "Frost Armor",
        school: :frost,
        effects: [
          %Effect{
            index: 0,
            type: :trigger_spell,
            trigger_spell_id: 6136
          }
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}

      {_target, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [
               %{
                 type: :trigger_spell,
                 source_guid: 999,
                 source_level: 10,
                 target_guid: 1,
                 spell_id: 6136
               }
             ] = events
    end
  end

  describe "spell power bonuses" do
    test "direct damage gains spell power scaled by cast time" do
      spell = %Spell{
        id: 133,
        name: "Fireball",
        school: :fire,
        cast_time_ms: 3_500,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 5, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10, spell_damage_bonus: %{fire: 100}}

      {target, _events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert target.unit.health == 0
      assert [%{damage: 105}] = elem(SpellEffect.receive(target_fixture(), context, spell, 1_000), 1)
    end

    test "instant spells use the minimum coefficient" do
      spell = %Spell{
        id: 133,
        name: "Fire Blast",
        school: :fire,
        cast_time_ms: 0,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 5, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10, spell_damage_bonus: %{fire: 70}}

      assert [%{damage: 35}] = elem(SpellEffect.receive(target_fixture(), context, spell, 1_000), 1)
    end

    test "wrong school bonus does not apply" do
      spell = %Spell{
        id: 133,
        name: "Fireball",
        school: :fire,
        cast_time_ms: 3_500,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 5, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10, spell_damage_bonus: %{shadow: 100}}

      assert [%{damage: 5}] = elem(SpellEffect.receive(target_fixture(), context, spell, 1_000), 1)
    end

    test "healing gains the healing bonus" do
      spell = %Spell{
        id: 2050,
        name: "Lesser Heal",
        school: :holy,
        cast_time_ms: 3_500,
        effects: [%Effect{index: 0, type: :heal, base_points: 5, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10, healing_bonus: 10}

      target = target_fixture()
      target = %{target | unit: %{target.unit | health: 1}}
      {target, _events} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.unit.health == 16
    end
  end
end
