defmodule ThistleTea.Game.Entity.Logic.AuraTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.WorldRef

  defp fixture_entity(opts \\ []) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        level: Keyword.get(opts, :level, 1),
        health: 100,
        max_health: 100,
        auras: []
      },
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp apply_spell(entity, caster_guid, caster_level, spell) do
    Aura.apply_spell(entity, caster_guid, caster_level, spell, 1_000)
  end

  defp frost_armor_fixture do
    %Spell{
      id: 168,
      name: "Frost Armor",
      school: :frost,
      cast_time_ms: 0,
      duration_ms: 600_000,
      range_yards: 0.0,
      mana_cost: 0,
      gcd_ms: 1500,
      attributes: MapSet.new(),
      effects: [
        %Effect{
          index: 1,
          type: :apply_aura,
          base_points: 29,
          die_sides: 0,
          aura: :mod_resistance,
          amplitude_ms: 0,
          misc_value: 1,
          implicit_target_a: :caster
        }
      ]
    }
  end

  defp clearcasting_fixture do
    %Spell{
      id: 11_213,
      name: "Arcane Concentration",
      duration_ms: -1,
      proc_type_mask: 0x10000,
      proc_chance: 100,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 0,
          die_sides: 0,
          aura: :proc_trigger_spell,
          trigger_spell_id: 12_536
        }
      ]
    }
  end

  defp vampiric_embrace_fixture do
    %Spell{
      id: 15_286,
      name: "Vampiric Embrace",
      school: :shadow,
      duration_ms: 60_000,
      proc_type_mask: 0xA0000,
      proc_chance: 100,
      proc_rule: %ProcRule{school_mask: 0x20},
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 19,
          die_sides: 1,
          base_dice: 1,
          aura: :dummy
        }
      ]
    }
  end

  describe "attacker_spell_hit_chance/1" do
    test "publishes school-masked victim hit modifiers" do
      heightened_senses = %Holder{
        spell: %Spell{id: 30_894},
        auras: [
          %AuraData{
            type: :mod_attacker_spell_hit_chance,
            amount: -2,
            misc_value: 0x7E
          }
        ]
      }

      mob = %Mob{unit: %Unit{auras: [heightened_senses]}}
      modifiers = Aura.attacker_spell_hit_chance(mob)

      assert modifiers == [{0x7E, -2}]
      assert Aura.versus_amount(modifiers, Spell.school_mask(:fire)) == -2
      assert Aura.versus_amount(modifiers, Spell.school_mask(:physical)) == 0
    end
  end

  defp root_spell do
    %Spell{
      id: 122,
      name: "Frost Nova",
      school: :frost,
      duration_ms: 8_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 0,
          die_sides: 0,
          aura: :mod_root
        }
      ]
    }
  end

  defp casting_time_modifier_fixture do
    %Spell{
      id: 11_070,
      spell_family: 3,
      attributes: MapSet.new([:passive]),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: -101,
          base_dice: 1,
          die_sides: 1,
          aura: :add_flat_modifier,
          misc_value: 10,
          class_mask: 1 <<< 5
        }
      ]
    }
  end

  describe "apply_spell/5" do
    test "appends a holder with the spell to the unit" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert [%Holder{spell: ^spell, caster_guid: 1, slot: 0}] = entity.unit.auras
    end

    test "returns the applied holder's duration event for player targets" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 1, health: 100, max_health: 100, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      {_character, events} = apply_spell(character, 1, 1, frost_armor_fixture())

      assert [%{type: :aura_duration, aura_slot: 0, duration_ms: 600_000}] =
               Enum.filter(events, &(&1.type == :aura_duration))
    end

    test "returns no duration event for mob targets" do
      {_entity, events} = apply_spell(fixture_entity(), 1, 1, frost_armor_fixture())

      assert Enum.filter(events, &(&1.type == :aura_duration)) == []
    end

    test "applies mod_resistance to the matching school field" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.unit.normal_resistance == 29
      assert entity.unit.holy_resistance == 0
    end

    test "layers mod_resistance on top of base resistance" do
      entity = put_in(fixture_entity().unit.base_normal_resistance, 7)
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.unit.base_normal_resistance == 7
      assert entity.unit.normal_resistance == 36
    end

    test "packs spell_id into the aura wire field at the holder slot" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert <<spell_at_slot_0::little-size(32), _rest::binary>> =
               <<entity.unit.aura::little-size(48 * 32)>>

      assert spell_at_slot_0 == spell.id
    end

    test "marks the entity for broadcast" do
      entity = fixture_entity()
      spell = frost_armor_fixture()

      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert entity.internal.broadcast_update? == true
    end

    test "emits client spell-modifier updates on apply and removal" do
      spell = casting_time_modifier_fixture()
      {entity, apply_events} = apply_spell(fixture_entity(), 1, 1, spell)

      assert Enum.any?(
               apply_events,
               &match?(
                 %{type: :spell_modifier, modifier_type: :flat, effect_index: 5, operation: 10, amount: -100},
                 &1
               )
             )

      {_entity, remove_events} = Aura.remove_spells(entity, [spell.id], 2_000)

      assert Enum.any?(
               remove_events,
               &match?(
                 %{type: :spell_modifier, modifier_type: :flat, effect_index: 5, operation: 10, amount: 0},
                 &1
               )
             )
    end

    test "keeps nonvisual passive effects off the client aura fields" do
      passive = casting_time_modifier_fixture()
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, passive)
      {entity, _events} = apply_spell(entity, 1, 1, frost_armor_fixture())

      assert [%Holder{spell: ^passive, slot: nil}, %Holder{spell: visible, slot: 0}] = entity.unit.auras
      assert visible.id == 168

      assert <<spell_at_slot_0::little-size(32), _rest::binary>> =
               <<entity.unit.aura::little-size(48 * 32)>>

      assert spell_at_slot_0 == visible.id
    end

    test "displays passive spells that have a visual" do
      spell = %{casting_time_modifier_fixture() | spell_visual: 1}

      {entity, _events} = apply_spell(fixture_entity(), 1, 1, spell)

      assert [%Holder{spell: ^spell, slot: 0}] = entity.unit.auras
    end

    test "applying two different spells fills two slots" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      other_spell = %{spell | id: 7000}

      {entity, _events} = apply_spell(entity, 1, 1, spell)
      {entity, _events} = apply_spell(entity, 1, 1, other_spell)

      assert length(entity.unit.auras) == 2
      assert Enum.map(entity.unit.auras, & &1.slot) == [0, 1]
      assert entity.unit.normal_resistance == 58
    end

    test "root aura halts active movement and emits a movement stop event" do
      entity =
        fixture_entity()
        |> put_in([Access.key!(:movement_block), Access.key!(:movement_flags)], 0x00400001)
        |> put_in([Access.key!(:movement_block), Access.key!(:duration)], 10_000)
        |> put_in([Access.key!(:movement_block), Access.key!(:spline_nodes)], [{10.0, 0.0, 0.0}])
        |> put_in([Access.key!(:movement_block), Access.key!(:spline_id)], 7)
        |> put_in([Access.key!(:internal), Access.key!(:movement_start_time)], ThistleTea.Game.Time.now())
        |> put_in([Access.key!(:internal), Access.key!(:movement_start_position)], {0.0, 0.0, 0.0})

      spell = root_spell()

      {entity, events} = apply_spell(entity, 999, 1, spell)

      assert [%{type: :movement_stopped}, %{type: :movement_root_changed, rooted?: true}] = events
      assert (entity.movement_block.movement_flags &&& 0x08000000) != 0
      assert (entity.movement_block.movement_flags &&& 0x00400001) == 0
      assert entity.movement_block.spline_nodes == []
      assert entity.internal.movement_start_time == nil
    end

    test "expiring root aura emits an unroot event" do
      entity = fixture_entity()
      spell = root_spell()

      {entity, _events} = apply_spell(entity, 999, 1, spell)
      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, events} = Aura.expire_due(entity, future + 1)

      assert [%{type: :movement_root_changed, rooted?: false}] = events
      assert (entity.movement_block.movement_flags &&& 0x08000000) == 0
    end

    test "expiring root aura still unroots after client movement packets clobber the flags" do
      entity = fixture_entity()
      spell = root_spell()

      {entity, _events} = apply_spell(entity, 999, 1, spell)
      entity = put_in(entity, [Access.key!(:movement_block), Access.key!(:movement_flags)], 0x1000)

      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, events} = Aura.expire_due(entity, future + 1)

      assert [%{type: :movement_root_changed, rooted?: false}] = events
      refute entity.internal.rooted?
    end

    test "runs VMangos aura removal scripts after expiration" do
      entity = fixture_entity()

      spell = %Spell{
        id: 19_386,
        script_name: "spell_hunter_wyvern_sting",
        duration_ms: 12_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun}]
      }

      {entity, _events} = apply_spell(entity, 999, 60, spell)
      expires_at = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {_entity, events} = Aura.expire_due(entity, expires_at)

      assert Enum.any?(events, fn event ->
               event.type == :trigger_spell and event.source_guid == 999 and event.target_guid == 1 and
                 event.spell_id == 24_131
             end)
    end

    test "ignores spell IDs without the VMangos aura script label" do
      entity = fixture_entity()

      spell = %Spell{
        id: 19_386,
        duration_ms: 12_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stun}]
      }

      {entity, _events} = apply_spell(entity, 999, 60, spell)
      expires_at = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {_entity, events} = Aura.expire_due(entity, expires_at)

      refute Enum.any?(events, &(&1.type == :trigger_spell))
    end
  end

  describe "tick/2 with periodic_damage" do
    defp dot_fixture do
      %Spell{
        id: 11_366,
        name: "Pyroblast",
        school: :fire,
        cast_time_ms: 6_000,
        duration_ms: 12_000,
        range_yards: 40.0,
        mana_cost: 0,
        gcd_ms: 1500,
        attributes: MapSet.new(),
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: 50,
            die_sides: 0,
            aura: :periodic_damage,
            amplitude_ms: 3_000,
            misc_value: 0,
            implicit_target_a: :target_enemy
          }
        ]
      }
    end

    test "applies damage when amplitude elapses and advances the tick" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      first_tick_at = aura.next_tick_at

      {entity, events} = Aura.tick(entity, first_tick_at)

      assert entity.unit.health == 50
      assert [%{type: :spell_damage, damage: 50, periodic?: true}] = events
      [updated] = entity.unit.auras
      [updated_aura] = updated.auras
      amplitude = spell.effects |> hd() |> Map.fetch!(:amplitude_ms)
      assert updated_aura.next_tick_at == first_tick_at + amplitude
    end

    test "does not tick before amplitude has elapsed" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      before = aura.next_tick_at - 1

      {entity, events} = Aura.tick(entity, before)

      assert entity.unit.health == 100
      assert events == []
    end

    test "catches up multiple missed ticks in one call" do
      entity = fixture_entity()
      spell = dot_fixture()
      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      far_future = aura.next_tick_at + 7_000

      {entity, _events} = Aura.tick(entity, far_future)

      [updated] = entity.unit.auras
      [updated_aura] = updated.auras
      assert updated_aura.next_tick_at > far_future
    end
  end

  describe "tick/2 with periodic_heal" do
    test "restores health when amplitude elapses and advances the tick" do
      entity = %{fixture_entity() | unit: %Unit{level: 1, health: 40, max_health: 100, auras: []}}

      spell = %Spell{
        id: 139,
        name: "Renew",
        school: :holy,
        duration_ms: 12_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 25,
            die_sides: 0,
            aura: :periodic_heal,
            amplitude_ms: 3_000
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      first_tick_at = aura.next_tick_at

      {entity, events} = Aura.tick(entity, first_tick_at)

      assert entity.unit.health == 65

      assert [
               %{
                 type: :periodic_aura_log,
                 source_guid: 999,
                 target_guid: 1,
                 spell_id: 139,
                 aura_type: :periodic_heal,
                 amount: 25
               },
               %{
                 type: :spell_heal,
                 source_guid: 999,
                 target_guid: 1,
                 spell_id: 139,
                 periodic?: true,
                 proc_type: :deal_helpful_periodic
               },
               %{type: :heal_threat, source_guid: 999, target_guid: 1, amount: 12.5}
             ] = events

      [updated] = entity.unit.auras
      [updated_aura] = updated.auras
      assert updated_aura.next_tick_at == first_tick_at + 3_000
    end

    test "restores mana and logs periodic energize ticks" do
      entity = %{
        fixture_entity()
        | unit: %Unit{level: 1, health: 100, max_health: 100, power1: 10, max_power1: 100, auras: []}
      }

      spell = %Spell{
        id: 430,
        name: "Drink",
        duration_ms: 18_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 50,
            die_sides: 0,
            aura: :periodic_energize,
            amplitude_ms: 3_000,
            misc_value: 0
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras
      first_tick_at = aura.next_tick_at

      {entity, events} = Aura.tick(entity, first_tick_at)

      assert entity.unit.power1 == 60

      assert [
               %{
                 type: :periodic_aura_log,
                 source_guid: 999,
                 target_guid: 1,
                 spell_id: 430,
                 aura_type: :periodic_energize,
                 amount: 50,
                 misc_value: 0
               }
             ] = events
    end

    test "grants and logs rage energize ticks" do
      entity = %{
        fixture_entity()
        | unit: %Unit{
            level: 1,
            health: 100,
            max_health: 100,
            power_type: 1,
            power2: 100,
            max_power2: 1_000,
            auras: []
          }
      }

      spell = %Spell{
        id: 29_131,
        name: "Bloodrage",
        duration_ms: 10_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 9,
            die_sides: 1,
            base_dice: 1,
            aura: :periodic_energize,
            amplitude_ms: 1_000,
            misc_value: 1
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 999, 1, spell)

      [holder] = entity.unit.auras
      [aura] = holder.auras

      {entity, events} = Aura.tick(entity, aura.next_tick_at)

      assert entity.unit.power2 == 110

      assert [
               %{
                 type: :periodic_aura_log,
                 spell_id: 29_131,
                 aura_type: :periodic_energize,
                 amount: 10,
                 misc_value: 1
               }
             ] = events
    end
  end

  describe "reactions/3" do
    test "returns trigger spell events for on-hit proc auras" do
      entity = fixture_entity()

      spell = %Spell{
        id: 168,
        name: "Frost Armor",
        school: :frost,
        duration_ms: 600_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :damage_shield,
            trigger_spell_id: 6136
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      assert {_entity,
              [
                %{
                  type: :trigger_spell,
                  source_guid: 1,
                  source_level: 10,
                  target_guid: 999,
                  spell_id: 6136
                }
              ]} = Aura.reactions(entity, :hit_taken, %{attacker_guid: 999})
    end

    test "fires proc-trigger auras when dealing harmful spells" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 1, 10, clearcasting_fixture())

      context = %{
        spell: %Spell{id: 116, school: :frost},
        outcome: :normal,
        proc_type: :deal_harmful_spell,
        victim_guid: 999,
        now: 1_000
      }

      assert {_entity,
              [
                %{
                  type: :trigger_spell,
                  source_guid: 1,
                  target_guid: 999,
                  spell_id: 12_536,
                  triggering_spell_id: 11_213
                }
              ]} = Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "honors crit-only proc rules for spell procs" do
      entity = fixture_entity()
      spell = %{clearcasting_fixture() | proc_rule: %ProcRule{proc_ex: 0x2}}

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      context = %{
        spell: %Spell{id: 116, school: :frost},
        proc_type: :deal_harmful_spell,
        victim_guid: 999,
        now: 1_000
      }

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_dealt, Map.put(context, :outcome, :normal))

      assert {_entity, [%{type: :trigger_spell, spell_id: 12_536}]} =
               Aura.reactions(entity, :spell_hit_dealt, Map.put(context, :outcome, :crit))
    end

    test "treats cast-end proc rules as eligible" do
      entity = fixture_entity()
      spell = %{clearcasting_fixture() | proc_rule: %ProcRule{proc_ex: 0x80000}}

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      context = %{
        spell: %Spell{id: 116, school: :frost},
        outcome: :normal,
        proc_type: :deal_harmful_spell,
        victim_guid: 999,
        now: 1_000
      }

      assert {_entity, [%{type: :trigger_spell, spell_id: 12_536}]} =
               Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "never procs a spell aura from its own spell" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 1, 10, clearcasting_fixture())

      context = %{
        spell: clearcasting_fixture(),
        outcome: :normal,
        proc_type: :deal_harmful_spell,
        victim_guid: 999,
        now: 1_000
      }

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "respects proc cooldowns on spell procs" do
      entity = fixture_entity()
      spell = %{clearcasting_fixture() | proc_rule: %ProcRule{cooldown_ms: 1_000}}

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      context = %{
        spell: %Spell{id: 116, school: :frost},
        outcome: :normal,
        proc_type: :deal_harmful_spell,
        victim_guid: 999,
        now: 1_000
      }

      {entity, [%{type: :trigger_spell}]} = Aura.reactions(entity, :spell_hit_dealt, context)

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_dealt, %{context | now: 1_500})
      assert {_entity, [%{type: :trigger_spell}]} = Aura.reactions(entity, :spell_hit_dealt, %{context | now: 2_100})
    end

    test "fires kill-flagged proc auras on kills that grant experience" do
      entity = fixture_entity()

      spirit_tap = %Spell{
        id: 15_338,
        name: "Spirit Tap",
        duration_ms: -1,
        proc_type_mask: 0x2,
        proc_chance: 100,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :proc_trigger_spell,
            trigger_spell_id: 15_271
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, spirit_tap)

      assert {_entity,
              [
                %{
                  type: :trigger_spell,
                  source_guid: 1,
                  spell_id: 15_271,
                  triggering_spell_id: 15_338
                }
              ]} = Aura.reactions(entity, :kill, %{victim_guid: 999, now: 1_000})
    end

    test "kill procs skip auras without the kill proc flag" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 1, 10, clearcasting_fixture())

      assert {_entity, []} = Aura.reactions(entity, :kill, %{victim_guid: 999, now: 1_000})
    end

    test "vampiric embrace heals the priest's party from their shadow damage" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 7, 60, vampiric_embrace_fixture())

      context = %{
        attacker_guid: 7,
        spell: %Spell{id: 10_894, name: "Shadow Word: Pain", school: :shadow},
        proc_type: :take_harmful_periodic,
        outcome: :normal,
        damage: 100,
        now: 1_000
      }

      assert {_entity,
              [
                %{
                  type: :trigger_spell,
                  source_guid: 7,
                  target_guid: 7,
                  spell_id: 15_290,
                  amount: 20,
                  resolve_targets?: true
                }
              ]} = Aura.reactions(entity, :spell_hit_taken, context)
    end

    test "vampiric embrace ignores shadow damage from other casters" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 7, 60, vampiric_embrace_fixture())

      context = %{
        attacker_guid: 8,
        spell: %Spell{id: 10_894, name: "Shadow Word: Pain", school: :shadow},
        proc_type: :take_harmful_periodic,
        outcome: :normal,
        damage: 100,
        now: 1_000
      }

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_taken, context)
    end

    test "vampiric embrace ignores non-shadow damage" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 7, 60, vampiric_embrace_fixture())

      context = %{
        attacker_guid: 7,
        spell: %Spell{id: 133, name: "Fireball", school: :fire},
        proc_type: :take_harmful_spell,
        outcome: :normal,
        damage: 100,
        now: 1_000
      }

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_taken, context)
    end

    test "periodic damage ticks fire take-side spell procs" do
      entity = fixture_entity()

      shadow_word_pain = %Spell{
        id: 10_894,
        name: "Shadow Word: Pain",
        school: :shadow,
        duration_ms: 18_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 49,
            die_sides: 1,
            base_dice: 1,
            aura: :periodic_damage,
            amplitude_ms: 3_000
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 7, 60, shadow_word_pain)
      {entity, _events} = apply_spell(entity, 7, 60, vampiric_embrace_fixture())

      [holder | _rest] = entity.unit.auras
      [aura] = holder.auras

      {_entity, events} = Aura.tick(entity, aura.next_tick_at)

      assert %{type: :trigger_spell, spell_id: 15_290, amount: 10, source_guid: 7} =
               Enum.find(events, &(&1.type == :trigger_spell))
    end

    test "fires proc-trigger auras on crit heals" do
      entity = fixture_entity()

      inspiration = %Spell{
        id: 14_892,
        name: "Inspiration",
        duration_ms: -1,
        proc_type_mask: 0x15550,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x2},
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :proc_trigger_spell,
            trigger_spell_id: 14_893
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, inspiration)

      context = %{
        spell: %Spell{id: 2054, name: "Heal", school: :holy},
        proc_type: :deal_helpful_spell,
        victim_guid: 42,
        now: 1_000
      }

      assert {_entity, []} = Aura.reactions(entity, :spell_hit_dealt, Map.put(context, :outcome, :normal))

      assert {_entity, [%{type: :trigger_spell, spell_id: 14_893, target_guid: 42}]} =
               Aura.reactions(entity, :spell_hit_dealt, Map.put(context, :outcome, :crit))
    end

    test "spends charges of trigger-less proc auras like Divine Favor" do
      entity = fixture_entity()

      divine_favor = %Spell{
        id: 20_216,
        name: "Divine Favor",
        duration_ms: 60_000,
        proc_type_mask: 0x14000,
        proc_chance: 101,
        proc_charges: 1,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 99,
            die_sides: 1,
            base_dice: 1,
            aura: :mod_spell_crit_chance
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, divine_favor)
      assert [%{spell: %Spell{id: 20_216}}] = entity.unit.auras

      context = %{
        spell: %Spell{id: 635, name: "Holy Light", school: :holy},
        proc_type: :deal_helpful_spell,
        outcome: :crit,
        victim_guid: 42,
        now: 1_000
      }

      {entity, _events} = Aura.reactions(entity, :spell_hit_dealt, context)
      assert entity.unit.auras == []
    end

    test "block-flagged procs fire when the victim blocks" do
      entity = fixture_entity()

      shield_spec = %Spell{
        id: 12_298,
        name: "Shield Specialization",
        duration_ms: -1,
        proc_type_mask: 0x2A8,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x40},
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :proc_trigger_spell,
            trigger_spell_id: 23_602
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, shield_spec)

      context = %{attacker_guid: 999, proc_type: :take_melee_swing, now: 1_000}

      assert {_entity, []} = Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :normal))

      assert {_entity, [%{type: :trigger_spell, spell_id: 23_602}]} =
               Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :block))
    end

    test "dodge-flagged procs fire when the victim dodges" do
      entity = fixture_entity()

      setup_talent = %Spell{
        id: 13_983,
        name: "Setup",
        duration_ms: -1,
        proc_type_mask: 0x20028,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x18},
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :proc_trigger_spell,
            trigger_spell_id: 15_250
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, setup_talent)

      context = %{attacker_guid: 999, proc_type: :take_melee_swing, now: 1_000}

      assert {_entity, []} = Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :normal))

      assert {_entity, [%{type: :trigger_spell, spell_id: 15_250}]} =
               Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :dodge))

      resisted_spell = %Spell{
        id: 133,
        school: :fire,
        effects: [%Effect{type: :school_damage}]
      }

      {_entity, events} = SpellEffect.receive_outcome(entity, 999, resisted_spell, :resist, 1_000)
      assert [%{type: :trigger_spell, spell_id: 15_250, target_guid: 999}] = events
    end

    test "Magic Absorption restores a percentage of maximum mana after a full resist" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | power1: 100, max_power1: 1_000}}

      magic_absorption = %Spell{
        id: 29_447,
        name: "Magic Absorption",
        duration_ms: -1,
        proc_type_mask: 0x20000,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x8, cooldown_ms: 1_000},
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :dummy,
            base_points: 4,
            die_sides: 1,
            base_dice: 1
          },
          %Effect{index: 1, type: :apply_aura, aura: :mod_resistance, base_points: 9, misc_value: 0x7E}
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 60, magic_absorption)
      resisted_spell = %Spell{id: 116, school: :frost, effects: [%Effect{type: :school_damage}]}

      assert {entity, [event]} = SpellEffect.receive_outcome(entity, 999, resisted_spell, :resist, 1_000)

      assert %{
               type: :trigger_spell,
               source_guid: 1,
               target_guid: 1,
               spell_id: 29_442,
               amount: 50,
               slot: 0
             } = event

      assert {_entity, []} = SpellEffect.receive_outcome(entity, 999, resisted_spell, :resist, 1_999)
      assert {_entity, [_event]} = SpellEffect.receive_outcome(entity, 999, resisted_spell, :resist, 2_000)
    end

    test "damage shields with block-only proc rules skip regular hits" do
      entity = fixture_entity()

      holy_shield = %Spell{
        id: 20_925,
        name: "Holy Shield",
        duration_ms: 10_000,
        proc_type_mask: 0x2A8,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x40},
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :damage_shield,
            trigger_spell_id: 20_929
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, holy_shield)

      context = %{attacker_guid: 999, proc_type: :take_melee_swing, now: 1_000}

      assert {_entity, []} = Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :normal))

      assert {_entity, [%{type: :trigger_spell, spell_id: 20_929}]} =
               Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :block))
    end

    test "plain damage shields skip avoided attacks" do
      entity = fixture_entity()

      spell = %Spell{
        id: 168,
        name: "Frost Armor",
        school: :frost,
        duration_ms: 600_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :damage_shield,
            trigger_spell_id: 6136
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, spell)

      context = %{attacker_guid: 999, proc_type: :take_melee_swing, now: 1_000}

      assert {_entity, []} = Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :dodge))
      assert {_entity, []} = Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :block))

      assert {_entity, [%{type: :trigger_spell, spell_id: 6136}]} =
               Aura.reactions(entity, :hit_taken, Map.put(context, :outcome, :crit))
    end

    test "ignite applies a dot worth a percentage of fire crit damage" do
      entity = fixture_entity()

      ignite = %Spell{
        id: 12_848,
        name: "Ignite",
        duration_ms: -1,
        proc_type_mask: 0x10000,
        proc_chance: 100,
        proc_rule: %ProcRule{school_mask: 0x4, proc_ex: 0x2},
        effects: [
          %Effect{index: 0, type: :apply_aura, base_points: 0, die_sides: 0, aura: :dummy}
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 60, ignite)

      context = %{
        spell: %Spell{id: 133, name: "Fireball", school: :fire},
        proc_type: :deal_harmful_spell,
        outcome: :crit,
        victim_guid: 999,
        damage: 500,
        now: 1_000
      }

      assert {_entity,
              [
                %{type: :trigger_spell, spell_id: 12_654, target_guid: 999, amount: 100}
              ]} = Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "master of elements refunds part of the crit spell's mana cost" do
      entity = fixture_entity()

      master_of_elements = %Spell{
        id: 29_076,
        name: "Master of Elements",
        duration_ms: -1,
        proc_type_mask: 0x10000,
        proc_chance: 100,
        proc_rule: %ProcRule{school_mask: 0x14, proc_ex: 0x2},
        effects: [
          %Effect{index: 0, type: :apply_aura, base_points: 29, die_sides: 1, base_dice: 1, aura: :dummy}
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 60, master_of_elements)

      context = %{
        spell: %Spell{id: 133, name: "Fireball", school: :fire, mana_cost: 410},
        proc_type: :deal_harmful_spell,
        outcome: :crit,
        victim_guid: 999,
        damage: 500,
        now: 1_000
      }

      assert {_entity,
              [
                %{type: :trigger_spell, spell_id: 29_077, target_guid: 1, amount: 123}
              ]} = Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "shapeshifting into a feral form procs furor and leader of the pack" do
      entity = fixture_entity()

      furor = %Spell{
        id: 17_061,
        name: "Furor",
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, base_points: 99, die_sides: 1, base_dice: 1, aura: :dummy}]
      }

      leader_of_the_pack = %Spell{
        id: 17_007,
        name: "Leader of the Pack",
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, base_points: 0, die_sides: 0, aura: :dummy}]
      }

      cat_form = %Spell{
        id: 768,
        name: "Cat Form",
        duration_ms: -1,
        effects: [
          %Effect{index: 0, type: :apply_aura, base_points: 0, die_sides: 0, aura: :mod_shapeshift, misc_value: 1}
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 40, furor)
      {entity, _events} = apply_spell(entity, 1, 40, leader_of_the_pack)
      {_entity, events} = apply_spell(entity, 1, 40, cat_form)

      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 24_932))
      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 17_099))
    end

    test "ignite damage scales with talent rank" do
      for {rank_spell_id, expected} <- [{11_119, 20}, {12_846, 60}, {12_848, 100}] do
        entity = fixture_entity()

        ignite = %Spell{
          id: rank_spell_id,
          name: "Ignite",
          duration_ms: -1,
          proc_type_mask: 0x10000,
          proc_chance: 100,
          proc_rule: %ProcRule{school_mask: 0x4, proc_ex: 0x2},
          effects: [%Effect{index: 0, type: :apply_aura, base_points: 0, die_sides: 0, aura: :dummy}]
        }

        {entity, _events} = apply_spell(entity, 1, 60, ignite)

        context = %{
          spell: %Spell{id: 133, name: "Fireball", school: :fire},
          proc_type: :deal_harmful_spell,
          outcome: :crit,
          victim_guid: 999,
          damage: 500,
          now: 1_000
        }

        assert {_entity, [%{type: :trigger_spell, spell_id: 12_654, amount: ^expected}]} =
                 Aura.reactions(entity, :spell_hit_dealt, context)
      end
    end

    test "master of elements refund scales with the dummy aura amount" do
      for {base_points, expected} <- [{9, 41}, {29, 123}] do
        entity = fixture_entity()

        master_of_elements = %Spell{
          id: if(base_points == 9, do: 29_074, else: 29_076),
          name: "Master of Elements",
          duration_ms: -1,
          proc_type_mask: 0x10000,
          proc_chance: 100,
          proc_rule: %ProcRule{school_mask: 0x14, proc_ex: 0x2},
          effects: [
            %Effect{index: 0, type: :apply_aura, base_points: base_points, die_sides: 1, base_dice: 1, aura: :dummy}
          ]
        }

        {entity, _events} = apply_spell(entity, 1, 60, master_of_elements)

        context = %{
          spell: %Spell{id: 133, name: "Fireball", school: :fire, mana_cost: 410},
          proc_type: :deal_harmful_spell,
          outcome: :crit,
          victim_guid: 999,
          damage: 500,
          now: 1_000
        }

        assert {_entity, [%{type: :trigger_spell, spell_id: 29_077, amount: ^expected}]} =
                 Aura.reactions(entity, :spell_hit_dealt, context)
      end
    end

    test "vampiric embrace heal scales with the damage dealt" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 7, 60, vampiric_embrace_fixture())

      for {damage, heal} <- [{50, 10}, {500, 100}] do
        context = %{
          attacker_guid: 7,
          spell: %Spell{id: 10_894, name: "Shadow Word: Pain", school: :shadow},
          proc_type: :take_harmful_periodic,
          outcome: :normal,
          damage: damage,
          now: 1_000
        }

        assert {_entity, [%{type: :trigger_spell, spell_id: 15_290, amount: ^heal}]} =
                 Aura.reactions(entity, :spell_hit_taken, context)
      end
    end

    test "illumination refunds the base mana cost on crit heals" do
      entity = fixture_entity()

      illumination = %Spell{
        id: 20_210,
        name: "Illumination",
        duration_ms: -1,
        proc_type_mask: 0x4400,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x2},
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 0,
            die_sides: 0,
            aura: :proc_trigger_spell,
            trigger_spell_id: 18_350
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 10, illumination)

      context = %{
        spell: %Spell{id: 635, name: "Holy Light", school: :holy, mana_cost: 35},
        proc_type: :deal_helpful_spell,
        outcome: :crit,
        victim_guid: 42,
        now: 1_000
      }

      assert {_entity,
              [
                %{
                  type: :trigger_spell,
                  spell_id: 20_272,
                  amount: 35,
                  source_guid: 1,
                  target_guid: 1
                }
              ]} = Aura.reactions(entity, :spell_hit_dealt, context)
    end

    test "helpful periodic ticks reach outgoing proc reactions" do
      hot_proc = %Spell{
        id: 90_001,
        duration_ms: -1,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_flags: 0x40000, proc_ex: 0x40000},
        effects: [
          %Effect{
            type: :apply_aura,
            aura: :proc_trigger_spell,
            trigger_spell_id: 90_002
          }
        ]
      }

      {entity, _events} = apply_spell(fixture_entity(), 1, 60, hot_proc)

      context = %{
        spell: %Spell{id: 139, name: "Renew", school: :holy},
        proc_type: :deal_helpful_periodic,
        outcome: :normal,
        victim_guid: 42,
        now: 1_000
      }

      assert {_entity, [%{type: :trigger_spell, spell_id: 90_002, target_guid: 42}]} =
               Aura.reactions(entity, :spell_hit_dealt, context)
    end
  end

  describe "movement speed modifiers" do
    test "mod_decrease_speed layers on top of base movement speeds" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{
            position: {0.0, 0.0, 0.0, 0.0},
            walk_speed: 2.5,
            run_speed: 7.0,
            run_back_speed: 4.5,
            swim_speed: 4.7,
            swim_back_speed: 2.5,
            base_walk_speed: 2.5,
            base_run_speed: 7.0,
            base_run_back_speed: 4.5,
            base_swim_speed: 4.7,
            base_swim_back_speed: 2.5
          }
      }

      spell = %Spell{
        id: 6136,
        name: "Chilled",
        school: :frost,
        duration_ms: 5_000,
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: -31,
            die_sides: 1,
            base_dice: 1,
            aura: :mod_decrease_speed
          }
        ]
      }

      {entity, events} = apply_spell(entity, 1, 1, spell)

      assert entity.movement_block.base_run_speed == 7.0
      assert_in_delta entity.movement_block.run_speed, 4.9, 0.000001
      assert [%{type: :movement_speed_changed, speed: speed}] = events
      assert_in_delta speed, 4.9, 0.000001
    end

    test "overlapping slows apply only the strongest one" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0, base_run_speed: 7.0}
      }

      slow = fn id, amount ->
        %Spell{
          id: id,
          school: :frost,
          duration_ms: 8_000,
          effects: [%Effect{index: 0, type: :apply_aura, base_points: amount, aura: :mod_decrease_speed}]
        }
      end

      {entity, _events} = apply_spell(entity, 1, 1, slow.(120, -50))
      {entity, _events} = apply_spell(entity, 1, 1, slow.(11_113, -70))

      assert_in_delta entity.movement_block.run_speed, 7.0 * 0.3, 0.000001
    end

    test "the strongest speed buff multiplies with the strongest slow" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0, base_run_speed: 7.0}
      }

      sprint = %Spell{
        id: 2983,
        duration_ms: 15_000,
        effects: [%Effect{index: 0, type: :apply_aura, base_points: 50, aura: :mod_increase_speed}]
      }

      cheetah = %Spell{
        id: 5118,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, base_points: 30, aura: :mod_increase_speed}]
      }

      chill = %Spell{
        id: 120,
        school: :frost,
        duration_ms: 8_000,
        effects: [%Effect{index: 0, type: :apply_aura, base_points: -50, aura: :mod_decrease_speed}]
      }

      {entity, _events} = apply_spell(entity, 1, 1, sprint)
      {entity, _events} = apply_spell(entity, 1, 1, cheetah)
      {entity, _events} = apply_spell(entity, 1, 1, chill)

      assert_in_delta entity.movement_block.run_speed, 7.0 * 1.5 * 0.5, 0.000001
    end

    test "expiring mod_decrease_speed restores base movement speeds" do
      entity = %{
        fixture_entity()
        | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0, base_run_speed: 7.0}
      }

      spell = %Spell{
        id: 6136,
        name: "Chilled",
        school: :frost,
        duration_ms: 5_000,
        effects: [
          %Effect{
            index: 1,
            type: :apply_aura,
            base_points: -31,
            die_sides: 1,
            base_dice: 1,
            aura: :mod_decrease_speed
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 1, spell)
      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, events} = Aura.expire_due(entity, future + 1)

      assert entity.movement_block.base_run_speed == 7.0
      assert entity.movement_block.run_speed == 7.0
      assert [%{type: :movement_speed_changed, speed: 7.0}] = events
    end
  end

  describe "expire_due/2" do
    test "removes expired holders and reverses their mods" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, _events} = Aura.expire_due(entity, future + 1)

      assert entity.unit.auras == []
      assert entity.unit.normal_resistance == 0
    end

    test "removing expired holders preserves base resistance" do
      entity = put_in(fixture_entity().unit.base_normal_resistance, 7)
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      future = entity.unit.auras |> hd() |> Map.fetch!(:expires_at)
      {entity, _events} = Aura.expire_due(entity, future + 1)

      assert entity.unit.auras == []
      assert entity.unit.base_normal_resistance == 7
      assert entity.unit.normal_resistance == 7
    end

    test "keeps non-expired holders" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      now = entity.unit.auras |> hd() |> Map.fetch!(:applied_at)
      {entity, _events} = Aura.expire_due(entity, now + 1)

      assert length(entity.unit.auras) == 1
      assert entity.unit.normal_resistance == 29
    end
  end

  describe "rank and category stacking" do
    defp buff_spell(id, opts) do
      %Spell{
        id: id,
        name: Keyword.get(opts, :name, "Buff #{id}"),
        school: :arcane,
        duration_ms: 600_000,
        first_in_chain: Keyword.get(opts, :first_in_chain),
        rank: Keyword.get(opts, :rank),
        exclusive_category: Keyword.get(opts, :exclusive_category),
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: Keyword.get(opts, :amount, 9),
            die_sides: 0,
            aura: :mod_resistance,
            amplitude_ms: 0,
            misc_value: 1,
            implicit_target_a: :caster
          }
        ]
      }
    end

    test "higher rank replaces a lower rank of the same chain" do
      rank1 = buff_spell(1459, first_in_chain: 1459, rank: 1, amount: 9)
      rank2 = buff_spell(1460, first_in_chain: 1459, rank: 2, amount: 19)

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 1, 1, rank1)
      {entity, _events} = apply_spell(entity, 1, 1, rank2)

      assert [%Holder{spell: %Spell{id: 1460}}] = entity.unit.auras
      assert entity.unit.normal_resistance == 19
    end

    test "lower rank is not applied while a higher rank is active" do
      rank1 = buff_spell(1459, first_in_chain: 1459, rank: 1, amount: 9)
      rank2 = buff_spell(1460, first_in_chain: 1459, rank: 2, amount: 19)

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 1, 1, rank2)
      {entity, events} = apply_spell(entity, 1, 1, rank1)

      assert [%Holder{spell: %Spell{id: 1460}}] = entity.unit.auras
      assert events == []
    end

    test "blocked_by_stronger_rank?/2 detects a higher active rank" do
      rank1 = buff_spell(1459, first_in_chain: 1459, rank: 1)
      rank2 = buff_spell(1460, first_in_chain: 1459, rank: 2)

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 1, 1, rank2)

      assert Aura.blocked_by_stronger_rank?(entity, rank1)
      refute Aura.blocked_by_stronger_rank?(entity, rank2)
    end

    test "same exclusive category replaces across chains" do
      frost_armor = buff_spell(168, first_in_chain: 168, rank: 1, exclusive_category: :mage_armor)
      mage_armor = buff_spell(6117, first_in_chain: 6117, rank: 1, exclusive_category: :mage_armor)

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 1, 1, frost_armor)
      {entity, _events} = apply_spell(entity, 1, 1, mage_armor)

      assert [%Holder{spell: %Spell{id: 6117}}] = entity.unit.auras
    end

    test "same spell from a different caster replaces the existing holder" do
      spell = buff_spell(1459, first_in_chain: 1459, rank: 1)

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 10, 1, spell)
      {entity, _events} = apply_spell(entity, 20, 1, spell)

      assert [%Holder{caster_guid: 20}] = entity.unit.auras
    end

    test "spells without chain or category data still stack" do
      buff_a = buff_spell(100, [])
      buff_b = buff_spell(200, [])

      entity = fixture_entity()
      {entity, _events} = apply_spell(entity, 1, 1, buff_a)
      {entity, _events} = apply_spell(entity, 1, 1, buff_b)

      assert length(entity.unit.auras) == 2
    end
  end

  describe "cancel_spell/3" do
    test "canceling stealth removes overlapping stealth holders and clears the form" do
      entity = fixture_entity()

      stealth = %Spell{
        id: 1784,
        duration_ms: -1,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 30},
          %Effect{index: 1, type: :apply_aura, aura: :mod_stealth}
        ]
      }

      vanish = %Spell{
        id: 11_327,
        duration_ms: 10_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stealth}]
      }

      {entity, _events} = apply_spell(entity, 1, 1, stealth)
      {entity, _events} = apply_spell(entity, 1, 1, vanish)
      assert Bitwise.band(entity.unit.vis_flag, 0x02) != 0

      {entity, _events} = Aura.cancel_spell(entity, 1784, 2_000)

      assert entity.unit.auras == []
      assert entity.unit.shapeshift_form == 0
      assert entity.unit.aura == 0
      assert Bitwise.band(entity.unit.vis_flag, 0x02) == 0
    end

    test "removes a positive holder and reverses its mods" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      {entity, _events} = Aura.cancel_spell(entity, spell.id, 2_000)

      assert entity.unit.auras == []
      assert entity.unit.normal_resistance == 0
    end

    test "refuses to cancel a negative holder" do
      entity = fixture_entity()
      spell = root_spell()
      {entity, _events} = apply_spell(entity, 2, 1, spell)
      assert [%Holder{negative?: true}] = entity.unit.auras

      {entity, events} = Aura.cancel_spell(entity, spell.id, 2_000)

      assert [%Holder{}] = entity.unit.auras
      assert events == []
    end

    test "refuses to cancel a cant_cancel spell" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      spell = %{spell | attributes: MapSet.new([:cant_cancel])}
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      {entity, _events} = Aura.cancel_spell(entity, spell.id, 2_000)

      assert [%Holder{}] = entity.unit.auras
    end

    test "refuses to cancel a passive spell" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      spell = %{spell | attributes: MapSet.new([:passive])}
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      {entity, _events} = Aura.cancel_spell(entity, spell.id, 2_000)

      assert [%Holder{}] = entity.unit.auras
    end

    test "ignores spell ids without a matching holder" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      {entity, events} = Aura.cancel_spell(entity, 99_999, 2_000)

      assert [%Holder{}] = entity.unit.auras
      assert events == []
    end
  end

  describe "druid shapeshifting" do
    test "switches resources with cat and bear forms and restores mana" do
      entity = fixture_entity()

      entity = %{
        entity
        | unit: %{
            entity.unit
            | class: 11,
              race: 4,
              native_display_id: 55,
              display_id: 55,
              base_health: 100,
              power_type: 0,
              power2: 30,
              power4: 50
          }
      }

      cat = %Spell{
        id: 768,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 1}]
      }

      bear = %Spell{
        id: 5487,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 5}]
      }

      {entity, _events} = apply_spell(entity, 1, 1, cat)
      assert entity.unit.shapeshift_form == 1
      assert entity.unit.power_type == 3
      assert entity.unit.power4 == 0
      assert entity.unit.max_power4 == 100
      assert entity.unit.display_id == 892

      {entity, _events} = apply_spell(entity, 1, 1, bear)
      assert entity.unit.shapeshift_form == 5
      assert entity.unit.power_type == 1
      assert entity.unit.display_id == 2281

      {entity, _events} = Aura.cancel_spell(entity, bear.id, 2_000)
      assert entity.unit.shapeshift_form == 0
      assert entity.unit.power_type == 0
      assert entity.unit.power2 == 0
      assert entity.unit.display_id == 55
    end
  end

  describe "self_duration_events/2" do
    defp character_with_auras(holders) do
      %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 1, health: 100, max_health: 100, auras: holders}
      }
    end

    test "sends remaining duration, not original duration" do
      holder = %Holder{slot: 3, applied_at: 1_000, expires_at: 31_000, auras: []}
      character = character_with_auras([holder])

      assert [event] = Aura.self_duration_events(character, 11_000)
      assert event.aura_slot == 3
      assert event.duration_ms == 20_000
    end

    test "clamps already-expired holders to zero" do
      holder = %Holder{slot: 0, applied_at: 1_000, expires_at: 5_000, auras: []}
      character = character_with_auras([holder])

      assert [event] = Aura.self_duration_events(character, 9_000)
      assert event.duration_ms == 0
    end

    test "skips holders without a finite expiry" do
      holders = [
        %Holder{slot: 0, applied_at: 1_000, expires_at: nil, auras: []},
        %Holder{slot: 1, applied_at: 1_000, expires_at: -1, auras: []}
      ]

      assert Aura.self_duration_events(character_with_auras(holders), 2_000) == []
    end

    test "returns no events for non-character entities" do
      entity = fixture_entity()
      spell = frost_armor_fixture()
      {entity, _events} = apply_spell(entity, 1, 1, spell)

      assert Aura.self_duration_events(entity, 2_000) == []
    end
  end

  describe "regen auras and interrupts" do
    @not_seated 0x40000

    defp food_fixture do
      %Spell{
        id: 433,
        name: "Food",
        school: :physical,
        cast_time_ms: 0,
        duration_ms: 18_000,
        mana_cost: 0,
        gcd_ms: 0,
        aura_interrupt_flags: @not_seated,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 16,
            die_sides: 0,
            aura: :mod_regen,
            amplitude_ms: 0,
            misc_value: 0,
            implicit_target_a: :caster
          }
        ]
      }
    end

    test "sits the target when applying a not-seated aura" do
      {entity, events} = apply_spell(fixture_entity(), 1, 1, food_fixture())

      assert entity.unit.stand_state == 1
      assert Enum.any?(events, &(&1.type == :stand_state and &1.stand_state == 1))
    end

    test "food auras tick silently without applying direct aura healing" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | health: 50}}
      {entity, _events} = apply_spell(entity, 1, 1, food_fixture())

      {entity, events} = Aura.tick(entity, 1_000 + 5_000)

      assert entity.unit.health == 50
      assert events == []
    end

    test "drink auras tick silently without granting direct mana" do
      entity = %{
        fixture_entity()
        | unit: %Unit{level: 1, health: 100, max_health: 100, power_type: 0, power1: 10, max_power1: 100, auras: []}
      }

      spell = %Spell{
        id: 430,
        name: "Drink",
        duration_ms: 18_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            base_points: 41,
            die_sides: 0,
            aura: :mod_power_regen,
            amplitude_ms: 0,
            misc_value: 0
          }
        ]
      }

      {entity, _events} = apply_spell(entity, 1, 1, spell)
      {entity, events} = Aura.tick(entity, 1_000 + 5_000)

      assert entity.unit.power1 == 10
      assert events == []
    end

    test "remove_with_interrupt_flags removes matching auras only" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, food_fixture())
      {entity, _events} = apply_spell(entity, 1, 1, frost_armor_fixture())

      {entity, _events} = Aura.remove_with_interrupt_flags(entity, Aura.interrupt_mask(:move), 2_000)

      spell_ids = Enum.map(entity.unit.auras, & &1.spell.id)
      assert spell_ids == [168]
    end

    test "turn mask does not remove not-seated auras" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, food_fixture())

      {entity, _events} = Aura.remove_with_interrupt_flags(entity, Aura.interrupt_mask(:turn), 2_000)

      assert length(entity.unit.auras) == 1
    end
  end

  defp fire_ward_fixture do
    %Spell{
      id: 543,
      name: "Fire Ward",
      school: :fire,
      duration_ms: 30_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, base_points: 164, die_sides: 0, aura: :school_absorb, misc_value: 0x4}
      ]
    }
  end

  defp mana_shield_fixture do
    %Spell{
      id: 1463,
      name: "Mana Shield",
      school: :arcane,
      duration_ms: 60_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, base_points: 119, die_sides: 0, aura: :mana_shield, misc_value: 1}
      ]
    }
  end

  defp polymorph_fixture do
    %Spell{
      id: 118,
      name: "Polymorph",
      school: :arcane,
      duration_ms: 20_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, base_points: -1, die_sides: 1, base_dice: 1, aura: :mod_confuse},
        %Effect{index: 1, type: :apply_aura, base_points: 0, die_sides: 0, aura: :transform, misc_value: 16_372}
      ]
    }
  end

  defp arcane_intellect_fixture do
    %Spell{
      id: 1459,
      name: "Arcane Intellect",
      school: :arcane,
      duration_ms: 1_800_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, base_points: 1, die_sides: 1, base_dice: 1, aura: :mod_stat, misc_value: 3}
      ]
    }
  end

  defp blink_immunity_fixture do
    %Spell{
      id: 1953,
      name: "Blink",
      school: :arcane,
      duration_ms: 0,
      effects: [
        %Effect{
          index: 1,
          type: :apply_aura,
          base_points: -1,
          die_sides: 1,
          base_dice: 1,
          aura: :mechanic_immunity,
          misc_value: 12
        },
        %Effect{
          index: 2,
          type: :apply_aura,
          base_points: -1,
          die_sides: 1,
          base_dice: 1,
          aura: :mechanic_immunity,
          misc_value: 7
        }
      ]
    }
  end

  defp curse_fixture do
    %Spell{
      id: 702,
      name: "Curse of Weakness",
      school: :shadow,
      dispel_type: 2,
      duration_ms: 120_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: -3,
          die_sides: 1,
          base_dice: 1,
          aura: :mod_damage_taken,
          misc_value: 1
        }
      ]
    }
  end

  defp slow_fall_fixture do
    %Spell{
      id: 130,
      name: "Slow Fall",
      school: :arcane,
      duration_ms: 30_000,
      effects: [
        %Effect{index: 0, type: :apply_aura, base_points: 0, die_sides: 0, aura: :feather_fall}
      ]
    }
  end

  defp renew_fixture do
    %Spell{
      id: 139,
      name: "Renew",
      school: :holy,
      duration_ms: 15_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          base_points: 14,
          die_sides: 1,
          base_dice: 1,
          aura: :periodic_heal,
          amplitude_ms: 3_000
        }
      ]
    }
  end

  describe "absorb_damage/3" do
    test "fire ward absorbs fire damage and tracks remaining amount" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, fire_ward_fixture())

      {entity, remaining} = Aura.absorb_damage(entity, 100, :fire)

      assert remaining == 0
      assert [%Holder{auras: [%{amount: 64}]}] = entity.unit.auras
    end

    test "fire ward does not absorb frost damage" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, fire_ward_fixture())

      {_entity, remaining} = Aura.absorb_damage(entity, 100, :frost)

      assert remaining == 100
    end

    test "fire ward is removed when exhausted" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, fire_ward_fixture())

      {entity, remaining} = Aura.absorb_damage(entity, 200, :fire)

      assert remaining == 200 - 164
      assert entity.unit.auras == []
    end

    test "mana shield absorbs any school and drains mana" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | power1: 100, max_power1: 100}}
      {entity, _events} = apply_spell(entity, 1, 1, mana_shield_fixture())

      {entity, remaining} = Aura.absorb_damage(entity, 30, :physical)

      assert remaining == 0
      assert entity.unit.power1 == 40
    end

    test "mana shield absorb is limited by available mana" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | power1: 20, max_power1: 100}}
      {entity, _events} = apply_spell(entity, 1, 1, mana_shield_fixture())

      {entity, remaining} = Aura.absorb_damage(entity, 30, :fire)

      assert remaining == 20
      assert entity.unit.power1 == 0
    end
  end

  describe "mod_confuse" do
    test "is a negative aura" do
      {entity, _events} = apply_spell(fixture_entity(), 2, 1, polymorph_fixture())

      assert [%Holder{negative?: true}] = entity.unit.auras
    end

    test "transform changes display id and reverts on break" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | display_id: 49, native_display_id: 49}}
      {entity, _events} = apply_spell(entity, 2, 1, polymorph_fixture())

      assert entity.unit.display_id == 16_372

      entity = Aura.break_on_damage(entity, 2_000)
      assert entity.unit.auras == []
      assert entity.unit.display_id == 49
    end

    test "take_damage breaks confuse auras" do
      {entity, _events} = apply_spell(fixture_entity(), 2, 1, polymorph_fixture())

      entity = Core.take_damage(entity, 10, 2_000)

      assert entity.unit.auras == []
      assert entity.unit.health == 90
    end
  end

  describe "mod_stat" do
    test "arcane intellect raises intellect and max mana" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | base_intellect: 20, base_mana: 80, power1: 100, max_power1: 100}}

      {entity, _events} = apply_spell(entity, 1, 1, arcane_intellect_fixture())

      assert entity.unit.intellect == 22
      assert entity.unit.max_power1 == 100 + 2 * 15
    end

    test "stat and max mana revert when aura expires" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | base_intellect: 20, base_mana: 80, power1: 100, max_power1: 100}}

      {entity, _events} = apply_spell(entity, 1, 1, arcane_intellect_fixture())
      {entity, _events} = Aura.expire_due(entity, 1_000 + 1_800_001)

      assert entity.unit.intellect == 20
      assert entity.unit.max_power1 == 100
      assert entity.unit.power1 == 100
    end
  end

  describe "mechanic_immunity" do
    test "blink removes roots and stuns" do
      {entity, _events} = apply_spell(fixture_entity(), 2, 1, root_spell())
      assert Aura.rooted?(entity)

      {entity, _events} = apply_spell(entity, 1, 1, blink_immunity_fixture())

      refute Aura.rooted?(entity)
      spell_ids = Enum.map(entity.unit.auras, & &1.spell.id)
      assert spell_ids == [1953]
    end
  end

  describe "dispel/3" do
    test "removes a holder matching the dispel type" do
      {entity, _events} = apply_spell(fixture_entity(), 2, 1, curse_fixture())
      {entity, _events} = apply_spell(entity, 1, 1, frost_armor_fixture())

      {entity, _events} = Aura.dispel(entity, 2, 2_000)

      spell_ids = Enum.map(entity.unit.auras, & &1.spell.id)
      assert spell_ids == [168]
    end

    test "does nothing when no aura matches" do
      {entity, _events} = apply_spell(fixture_entity(), 1, 1, frost_armor_fixture())

      {entity, _events} = Aura.dispel(entity, 2, 2_000)

      assert length(entity.unit.auras) == 1
    end
  end

  describe "feather_fall" do
    test "sets safe fall movement flag and emits events on gain and loss" do
      {entity, events} = apply_spell(fixture_entity(), 1, 1, slow_fall_fixture())

      assert (entity.movement_block.movement_flags &&& 0x20000000) != 0
      assert Enum.any?(events, &(&1.type == :feather_fall_changed and &1.enabled? == true))

      {entity, events} = Aura.expire_due(entity, 1_000 + 30_001)
      assert (entity.movement_block.movement_flags &&& 0x20000000) == 0
      assert Enum.any?(events, &(&1.type == :feather_fall_changed and &1.enabled? == false))
    end
  end

  describe "periodic refresh" do
    test "reapplying the same spell keeps the periodic tick schedule" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | health: 50}}

      {entity, _events} = apply_spell(entity, 1, 1, renew_fixture())
      [%Holder{auras: [%{next_tick_at: first_tick}]}] = entity.unit.auras

      {entity, _events} = Aura.apply_spell(entity, 1, 1, renew_fixture(), 2_000)
      [%Holder{auras: [%{next_tick_at: tick_after_refresh}]}] = entity.unit.auras

      assert tick_after_refresh == first_tick
    end
  end

  describe "cross-caster stacking" do
    defp shadow_word_pain_fixture do
      %Spell{
        id: 589,
        name: "Shadow Word: Pain",
        school: :shadow,
        duration_ms: 18_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 10, amplitude_ms: 3_000}
        ]
      }
    end

    defp plain_buff_fixture do
      %Spell{
        id: 1243,
        name: "Power Word: Fortitude",
        duration_ms: 1_800_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: 3, misc_value: 2}]
      }
    end

    defp sunder_fixture do
      %Spell{
        id: 7386,
        name: "Sunder Armor",
        stack_amount: 5,
        custom_flags: 0x81,
        duration_ms: 30_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_resistance, base_points: -100, misc_value: 1}]
      }
    end

    test "DoTs from different casters coexist" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 100, 60, shadow_word_pain_fixture())
      {entity, _events} = apply_spell(entity, 200, 60, shadow_word_pain_fixture())

      assert [%Holder{caster_guid: 100}, %Holder{caster_guid: 200}] = entity.unit.auras
    end

    test "plain buffs from a second caster replace the first" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 100, 60, plain_buff_fixture())
      {entity, _events} = apply_spell(entity, 200, 60, plain_buff_fixture())

      assert [%Holder{caster_guid: 200}] = entity.unit.auras
    end

    test "sunder-style debuffs share one stack across casters" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 100, 60, sunder_fixture())
      {entity, _events} = apply_spell(entity, 100, 60, sunder_fixture())
      {entity, _events} = apply_spell(entity, 200, 60, sunder_fixture())

      assert [%Holder{stacks: 3}] = entity.unit.auras
    end
  end

  describe "talent effect plumbing" do
    test "max pool auras scale health and energy" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | class: 4, base_health: 80, power_type: 3, power4: 0, max_power4: 100}}

      vigor = aura_fixture(21_369, :mod_increase_energy, base_points: 10, misc_value: 3)
      survivalist = aura_fixture(20_579, :mod_increase_health_percent, base_points: 10)

      {entity, _events} = apply_spell(entity, 1, 60, vigor)
      {entity, _events} = apply_spell(entity, 1, 60, survivalist)

      assert entity.unit.max_power4 == 110
      assert entity.unit.max_health == 88
    end

    test "tactical mastery retains rage when switching stances" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | class: 1, power_type: 1, power2: 400, max_power2: 1_000}}

      tactical_mastery = aura_fixture(12_678, :override_class_scripts, misc_value: 833)
      {entity, _events} = apply_spell(entity, 1, 60, tactical_mastery)

      stance = %Spell{
        id: 71,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 18}]
      }

      {entity, _events} = apply_spell(entity, 1, 60, stance)

      assert entity.unit.power2 == 150
    end

    test "add_target_trigger auras fire their trigger at cast targets" do
      caster = fixture_entity()

      relentless = %Spell{
        id: 14_179,
        spell_family: 8,
        duration_ms: -1,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :add_target_trigger,
            base_points: 99,
            base_dice: 1,
            class_mask: 0x20000,
            trigger_spell_id: 14_181
          }
        ]
      }

      {caster, _events} = apply_spell(caster, 1, 60, relentless)

      matching = %Spell{id: 8647, spell_family: 8, family_flags_0: 0x20000}
      other = %Spell{id: 133, spell_family: 3, family_flags_0: 0x1}

      assert [%{type: :trigger_spell, target_guid: 77, spell_id: 14_181}] =
               Aura.target_trigger_events(caster, matching, [77])

      assert Aura.target_trigger_events(caster, other, [77]) == []
    end

    test "obs_mod_health auras tick percent-of-max healing" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | health: 50}}

      blood_craze = aura_fixture(16_488, :obs_mod_health, base_points: 2, amplitude_ms: 3_000, duration_ms: 6_000)
      {entity, _events} = apply_spell(entity, 1, 60, blood_craze)

      {entity, events} = Aura.tick(entity, 4_001)

      assert entity.unit.health == 52
      assert Enum.any?(events, &(&1.type == :periodic_aura_log and &1.amount == 2))
    end
  end

  defp aura_fixture(id, aura, opts) do
    %Spell{
      id: id,
      duration_ms: Keyword.get(opts, :duration_ms, -1),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: aura,
          base_points: Keyword.get(opts, :base_points, 0),
          misc_value: Keyword.get(opts, :misc_value, 0),
          amplitude_ms: Keyword.get(opts, :amplitude_ms, 0)
        }
      ]
    }
  end

  describe "sting and dispel mechanics" do
    defp sting_fixture(id) do
      %Spell{
        id: id,
        exclusive_category: :hunter_sting,
        duration_ms: 15_000,
        dispel_type: 4,
        attributes: MapSet.new([:negative]),
        effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 10, amplitude_ms: 3_000}]
      }
    end

    test "hunter stings are exclusive per caster" do
      entity = fixture_entity()

      {entity, _events} = apply_spell(entity, 100, 60, sting_fixture(1978))
      {entity, _events} = apply_spell(entity, 100, 60, sting_fixture(3034))
      {entity, _events} = apply_spell(entity, 200, 60, sting_fixture(1978))

      assert [%Holder{caster_guid: 100, spell: %Spell{id: 3034}}, %Holder{caster_guid: 200}] = entity.unit.auras
    end

    test "dispel removes as many auras as the effect's base points" do
      entity = fixture_entity()

      magic_buff = fn id ->
        %Spell{
          id: id,
          duration_ms: 30_000,
          dispel_type: 1,
          effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: 3}]
        }
      end

      {entity, _events} = apply_spell(entity, 1, 60, magic_buff.(1243))
      {entity, _events} = apply_spell(entity, 1, 60, magic_buff.(14_752))

      {entity, _events} = Aura.dispel(entity, 1, 2_000, nil, 2)

      assert entity.unit.auras == []
    end
  end

  describe "cat form energy" do
    test "entering cat form zeroes energy and later auras do not refill it" do
      entity = fixture_entity()
      entity = %{entity | unit: %{entity.unit | class: 11, base_health: 100, power4: 50, max_power4: 0}}

      cat = %Spell{
        id: 768,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 1}]
      }

      {entity, _events} = apply_spell(entity, 1, 1, cat)
      assert entity.unit.power4 == 0
      assert entity.unit.max_power4 == 100

      entity = %{entity | unit: %{entity.unit | power4: 42}}
      {entity, _events} = apply_spell(entity, 100, 60, plain_buff_fixture())

      assert entity.unit.power4 == 42
    end
  end
end
