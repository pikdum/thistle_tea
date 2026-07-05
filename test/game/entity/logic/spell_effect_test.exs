defmodule ThistleTea.Game.Entity.Logic.SpellEffectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
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

  defp dead_character_fixture do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 0, max_health: 100, max_power1: 50, level: 10, auras: []},
      player: %Player{flags: 0},
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
        attributes: MapSet.new([:channeled]),
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

    test "channeled spells apply secondary auras without the channel-ticked trigger aura" do
      spell = %Spell{
        id: 15_407,
        name: "Mind Flay",
        school: :shadow,
        duration_ms: 3_000,
        attributes: MapSet.new([:negative, :channeled]),
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :periodic_trigger_spell,
            trigger_spell_id: 16_568,
            amplitude_ms: 1_000
          },
          %Effect{index: 1, type: :apply_aura, aura: :mod_decrease_speed, base_points: -50, die_sides: 0}
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 20}

      {target, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [%{type: :trigger_spell, spell_id: 16_568}] = Enum.filter(events, &(&1.type == :trigger_spell))
      assert [%Holder{auras: [%{type: :mod_decrease_speed}]}] = target.unit.auras
    end

    test "resurrect stores a pending resurrect with the caster's cast position" do
      spell = %Spell{
        id: 2006,
        name: "Resurrection",
        school: :holy,
        effects: [%Effect{index: 0, type: :resurrect, base_points: 34, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 40, caster_position: {0, 1.0, 2.0, 3.0}}

      {target, events} = SpellEffect.receive(dead_character_fixture(), context, spell, 1_000)

      assert target.internal.pending_resurrect == %{
               caster_guid: 999,
               position: {0, 1.0, 2.0, 3.0},
               health: 34,
               mana: 17
             }

      assert [%{type: :resurrect_request, source_guid: 999, spell_id: 2006, health: 34, mana: 17}] = events
    end

    test "resurrect does nothing for non-player targets" do
      spell = %Spell{
        id: 2006,
        name: "Resurrection",
        school: :holy,
        effects: [%Effect{index: 0, type: :resurrect, base_points: 34, die_sides: 0}]
      }

      target = target_fixture()
      dead_mob = %{target | unit: %{target.unit | health: 0}}

      assert {%Mob{internal: %Internal{pending_resurrect: nil}}, []} =
               SpellEffect.receive(dead_mob, %CastContext{caster_guid: 999, caster_level: 40}, spell, 1_000)
    end

    test "persistent area auras do not apply directly on hit (area effect process handles ticks)" do
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

      assert target.unit.health == 20
      assert events == []
    end

    test "heal effects restore health and emit heal threat for the effective gain" do
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
      assert [%{type: :heal_threat, source_guid: 999, target_guid: 1, amount: 5.0}] = events
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

    test "leap effect emits a teleport event ahead of the caster" do
      spell = %Spell{
        id: 1953,
        name: "Blink",
        school: :arcane,
        effects: [%Effect{index: 0, type: :leap, radius_yards: 20.0}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}
      caster = target_fixture()

      {_caster, events} = SpellEffect.receive(caster, context, spell, 1_000)

      assert [%{type: :leap, position: {x, y, z, o}}] = events
      assert_in_delta x, 20.0, 0.001
      assert_in_delta y, 0.0, 0.001
      assert z == 0.0
      assert o == 0.0
    end

    test "teleport_units effect emits a spell target teleport event" do
      spell = %Spell{
        id: 3561,
        name: "Teleport: Stormwind",
        school: :arcane,
        effects: [%Effect{index: 0, type: :teleport_units}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}

      {_caster, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [%{type: :teleport_to_spell_target, spell_id: 3561}] = events
    end

    test "create_item effect emits a create_item event" do
      spell = %Spell{
        id: 5504,
        name: "Conjure Water",
        school: :arcane,
        effects: [%Effect{index: 0, type: :create_item, base_points: 1, die_sides: 1, misc_value: 5350}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}

      {_caster, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [%{type: :create_item, item_id: 5350, count: 2}] = events
    end

    test "interrupt_cast clears the target's cast" do
      spell = %Spell{
        id: 2139,
        name: "Counterspell",
        school: :arcane,
        effects: [%Effect{index: 0, type: :interrupt_cast}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}

      target = target_fixture()
      target = %{target | internal: %{target.internal | casting: %Cast{}}}

      {target, _events} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.internal.casting == nil
    end

    test "mod_damage_taken reduces incoming spell damage" do
      dampen = %Spell{
        id: 604,
        name: "Dampen Magic",
        school: :arcane,
        duration_ms: 600_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, base_points: -11, die_sides: 1, aura: :mod_damage_taken, misc_value: 126}
        ]
      }

      target = target_fixture()
      {target, _} = Aura.apply_spell(target, 1, 10, dampen, 1_000)

      fireball = %Spell{
        id: 133,
        name: "Fireball",
        school: :fire,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 15, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}
      {target, events} = SpellEffect.receive(target, context, fireball, 1_000)

      assert [%{type: :spell_damage, damage: 5}] = events
      assert target.unit.health == 15
    end

    test "mod_healing modifies incoming heals" do
      amplify = %Spell{
        id: 1008,
        name: "Amplify Magic",
        school: :arcane,
        duration_ms: 600_000,
        effects: [
          %Effect{index: 1, type: :apply_aura, base_points: 29, die_sides: 1, aura: :mod_healing, misc_value: 126}
        ]
      }

      target = target_fixture()
      target = %{target | unit: %{target.unit | health: 1, max_health: 100}}
      {target, _} = Aura.apply_spell(target, 1, 10, amplify, 1_000)

      heal = %Spell{
        id: 2050,
        name: "Lesser Heal",
        school: :holy,
        effects: [%Effect{index: 0, type: :heal, base_points: 5, die_sides: 0}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10}
      {target, _events} = SpellEffect.receive(target, context, heal, 1_000)

      assert target.unit.health == 1 + 5 + 30
    end
  end
end
