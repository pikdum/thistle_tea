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

  describe "receive/3" do
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

      {target, events} = SpellEffect.receive(target_fixture(), context, spell)

      assert target.unit.health == 0
      assert target.unit.auras == []
      assert [%{type: :spell_damage, damage: 50, source_guid: 999, target_guid: 1}] = events
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

      {target, events} = SpellEffect.receive(target_fixture(), context, spell)

      assert target.unit.health == 0
      assert [%{type: :spell_damage, damage: 24, periodic?: true, spell_id: 10}] = events
    end
  end
end
