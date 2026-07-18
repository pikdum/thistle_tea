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
  alias ThistleTea.Game.WorldRef

  defp target_fixture do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 20, max_health: 20, level: 1, auras: []},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp dead_character_fixture do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 0, max_health: 100, max_power1: 50, level: 10, auras: []},
      player: %Player{flags: 0},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  describe "receive/4" do
    test "ranged weapon damage uses target attacker-power auras" do
      spell = %Spell{
        id: 75,
        school: :physical,
        dmg_class: 3,
        effects: [%Effect{type: :weapon_damage, base_points: 0}]
      }

      context = %CastContext{
        caster_guid: 999,
        caster_level: 60,
        attack_power: 0,
        attack_time_ms: 1_400,
        attack_skill: 300,
        weapon_base_min: 10,
        weapon_base_max: 10,
        melee_crit_chance: 0.0,
        spell_crit_chance: 0.0
      }

      mark = %Holder{
        spell: %Spell{id: 14_325},
        caster_guid: 999,
        auras: [%ThistleTea.Game.Aura{type: :ranged_attack_power_attacker_bonus, amount: 110}]
      }

      unmarked = %{target_fixture() | unit: %Unit{health: 500, max_health: 500, level: 1, auras: []}}
      marked = %{unmarked | unit: %{unmarked.unit | auras: [mark]}}

      {_unmarked, [unmarked_event]} = SpellEffect.receive(unmarked, context, spell, 1_000)
      {_marked, [marked_event]} = SpellEffect.receive(marked, context, spell, 1_000)

      assert marked_event.damage - unmarked_event.damage == 11
    end

    test "caster-targeted trigger effects fire at the caster, other caster effects stay filtered" do
      spell = %Spell{
        id: 23_881,
        school: :physical,
        effects: [
          %Effect{index: 0, type: :school_damage, base_points: 10, implicit_target_a: :target_enemy},
          %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 23_885, implicit_target_a: :caster},
          %Effect{index: 2, type: :heal, base_points: 50, implicit_target_a: :caster}
        ]
      }

      context = %CastContext{caster_guid: 999, caster_level: 60, target_role: :other, spell: spell}
      target = %{target_fixture() | unit: %Unit{health: 500, max_health: 500, level: 60, auras: []}}

      {target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert Enum.any?(
               events,
               &match?(%{type: :trigger_spell, source_guid: 999, target_guid: 999, spell_id: 23_885}, &1)
             )

      assert target.unit.health < 500
      refute Enum.any?(events, &(&1.type == :heal_entity))
    end

    test "multiple weapon-damage effects fold into a single strike" do
      spell = %Spell{
        id: 53,
        school: :physical,
        effects: [
          %Effect{index: 0, type: :weapon_percent_damage, base_points: 150},
          %Effect{index: 1, type: :normalized_weapon_damage, base_points: 15}
        ]
      }

      context = %CastContext{
        caster_guid: 999,
        caster_level: 60,
        attack_power: 0,
        weapon_base_min: 100,
        weapon_base_max: 100,
        normalized_speed: 1.7
      }

      target = %{target_fixture() | unit: %Unit{health: 500, max_health: 500, level: 60, auras: []}}

      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert [%{type: :spell_damage, damage: 172}] = Enum.filter(events, &(&1.type == :spell_damage))
    end

    test "direct magic damage uses the snapshotted spell crit chance" do
      spell = %Spell{id: 133, school: :fire, dmg_class: 1, effects: [%Effect{type: :school_damage, base_points: 100}]}
      context = %CastContext{caster_guid: 999, caster_level: 10, spell_crit_chance: 100.0}
      target = %{target_fixture() | unit: %Unit{health: 500, max_health: 500, level: 10, auras: []}}

      {target, [event]} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.unit.health == 350
      assert event.damage == 150
      assert event.crit?
    end

    test "the DBC cannot-crit attribute suppresses direct spell crits" do
      spell = %Spell{
        id: 133,
        school: :fire,
        dmg_class: 1,
        attributes: MapSet.new([:cant_crit]),
        effects: [%Effect{type: :school_damage, base_points: 100}]
      }

      context = %CastContext{caster_guid: 999, caster_level: 10, spell_crit_chance: 100.0}
      target = %{target_fixture() | unit: %Unit{health: 500, max_health: 500, level: 10, auras: []}}

      {target, [event]} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.unit.health == 400
      refute event.crit?
    end

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

    test "energize effects restore the matching power" do
      spell = %Spell{
        id: 2687,
        name: "Bloodrage",
        school: :physical,
        effects: [
          %Effect{
            index: 0,
            type: :energize,
            base_points: 99,
            die_sides: 1,
            base_dice: 1,
            misc_value: 1
          }
        ]
      }

      target = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 20, max_health: 20, level: 10, power_type: 1, power2: 0, max_power2: 1_000, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}

      {target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert target.unit.power2 == 100
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
        effects: [%Effect{index: 0, type: :create_item, base_points: 1, die_sides: 1, base_dice: 1, misc_value: 5350}]
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

    test "trap effects enqueue a timed game object summon" do
      spell = %Spell{
        id: 1499,
        name: "Freezing Trap",
        duration_ms: 60_000,
        effects: [%Effect{index: 0, type: :summon_game_object, misc_value: 2561}]
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}
      {_caster, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [%{type: :summon_game_object, entry: 2561, duration_ms: 60_000}] = events
    end

    test "summon-player effects preserve the DBC-selected target and caster destination" do
      spell = %Spell{id: 7720, effects: [%Effect{index: 0, type: :summon_player}]}

      context = %CastContext{
        caster_guid: 1,
        caster_level: 10,
        caster_zone: 12,
        caster_position: {%WorldRef{map_id: 0}, 1.0, 2.0, 3.0},
        selected_target_guid: 99
      }

      {_caster, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [
               %{
                 type: :summon_request,
                 source_guid: 1,
                 target_guid: 99,
                 amount: 12,
                 position: {%WorldRef{map_id: 0}, 1.0, 2.0, 3.0}
               }
             ] = events
    end

    test "summon-demon effects create a temporary owned summon at the destination" do
      spell = %Spell{id: 18_541, effects: [%Effect{index: 0, type: :summon_demon, misc_value: 11_859}]}

      context = %CastContext{
        caster_guid: 1,
        caster_level: 60,
        caster_position: {%WorldRef{map_id: 0}, 1.0, 2.0, 3.0},
        caster_orientation: 1.5,
        destination_position: {4.0, 5.0, 6.0}
      }

      {_caster, events} = SpellEffect.receive(target_fixture(), context, spell, 1_000)

      assert [
               %{
                 type: :summon_creature,
                 summon: %{
                   entry: 11_859,
                   owner_guid: 1,
                   position: {4.0, 5.0, 6.0, 1.5},
                   despawn_delay_ms: 3_600_000
                 }
               }
             ] = events
    end

    test "tame creature emits ownership data from the target entry" do
      spell = %Spell{id: 1515, effects: [%Effect{index: 0, type: :tame_creature}]}
      target = target_fixture()
      target = %{target | object: %{target.object | entry: 1234}}

      {_target, events} = SpellEffect.receive(target, %CastContext{caster_guid: 99, caster_level: 10}, spell, 1_000)

      assert [%{type: :tame_creature, source_guid: 99, entry: 1234}] = events
    end

    test "tame beast completion triggers VMangos' ownership spell" do
      spell = %Spell{id: 13_535, effects: [%Effect{index: 0, type: :dummy}]}
      target = target_fixture()
      context = %CastContext{caster_guid: 99, caster_level: 10}

      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert [%{type: :trigger_spell, source_guid: 99, target_guid: target_guid, spell_id: 13_481}] = events
      assert target_guid == target.object.guid
    end

    test "call, revive, and dismiss use the stable hunter pet entry" do
      character = dead_character_fixture()

      character = %{
        character
        | unit: %{character.unit | health: 100},
          internal: %{character.internal | active_pet_entry: 1234}
      }

      context = %CastContext{caster_guid: 1, caster_level: 10}

      call_pet = %Spell{id: 883, effects: [%Effect{index: 0, type: :summon_pet, misc_value: 0}]}
      {_character, events} = SpellEffect.receive(character, context, call_pet, 1_000)
      assert [%{type: :summon_pet, entry: 1234, spell_id: 883}] = events

      revive_pet = %Spell{id: 982, effects: [%Effect{index: 0, type: :revive_pet, misc_value: 0}]}
      {_character, events} = SpellEffect.receive(character, context, revive_pet, 1_000)
      assert [%{type: :summon_pet, entry: 1234, spell_id: 982}] = events

      dismiss_pet = %Spell{id: 2641, effects: [%Effect{index: 0, type: :dismiss_pet}]}
      {_character, events} = SpellEffect.receive(character, context, dismiss_pet, 1_000)
      assert [%{type: :dismiss_pet, source_guid: 1}] = events
    end

    test "totem effects preserve their elemental summon slot" do
      spell = %Spell{
        id: 3599,
        duration_ms: 30_000,
        effects: [%Effect{index: 0, type: :summon_totem, summon_slot: 1, misc_value: 2523}]
      }

      {_caster, events} = SpellEffect.receive(target_fixture(), %CastContext{caster_guid: 1}, spell, 1_000)

      assert [%{type: :summon_totem, entry: 2523, slot: 1, duration_ms: 30_000}] = events
    end

    test "mod_damage_taken reduces incoming spell damage" do
      dampen = %Spell{
        id: 604,
        name: "Dampen Magic",
        school: :arcane,
        duration_ms: 600_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: -11,
            die_sides: 1,
            base_dice: 1,
            aura: :mod_damage_taken,
            misc_value: 126
          }
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
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: 29,
            die_sides: 1,
            base_dice: 1,
            aura: :mod_healing,
            misc_value: 126
          }
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
