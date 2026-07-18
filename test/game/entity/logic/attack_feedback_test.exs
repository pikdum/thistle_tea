defmodule ThistleTea.Game.Entity.Logic.AttackFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  defp warrior(level \\ 60) do
    %Mob{
      unit: %Unit{power_type: 1, level: level, power2: 0, max_power2: 1_000, auras: []},
      internal: %Internal{}
    }
  end

  describe "receive/3" do
    test "grants dealt rage on a landed swing" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :normal, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 65
    end

    test "grants reduced rage when the swing is dodged" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :dodge, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 48
    end

    test "grants reduced rage when the swing is parried" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :parry, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 48
    end

    test "grants nothing on a miss" do
      entity = warrior()

      assert AttackFeedback.receive(entity, %{outcome: :miss, damage: 0, spell_id: nil}, 1_000) == entity
    end

    test "swings carrying a queued spell grant no rage" do
      entity = warrior()

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: 78}, 1_000) == entity
    end

    test "dodged rage abilities refund 82 percent of the cost" do
      entity = warrior()

      spell = %Spell{
        id: 78,
        mana_cost: 150,
        power_type: 1,
        attributes: MapSet.new([:discount_power_on_miss])
      }

      entity = AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, spell_id: 78}, spell, 1_000)

      assert entity.unit.power2 == 123
    end

    test "abilities without the refund attribute get nothing back on dodge" do
      entity = warrior()
      spell = %Spell{id: 78, mana_cost: 150, power_type: 1}

      assert AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, spell_id: 78}, spell, 1_000) == entity
    end

    test "abilities that land grant no rage even with the spell known" do
      entity = warrior()

      spell = %Spell{
        id: 78,
        mana_cost: 150,
        power_type: 1,
        attributes: MapSet.new([:discount_power_on_miss])
      }

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: 78}, spell, 1_000) == entity
    end

    test "ignores non-rage users" do
      entity = %Mob{
        unit: %Unit{power_type: 0, level: 60, power1: 0, max_power1: 100},
        internal: %Internal{}
      }

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: nil}, 1_000) == entity
    end

    test "a dodging target earns the warrior a combo point for overpower" do
      entity = %Character{
        object: %Object{guid: 5},
        unit: %Unit{class: 1, power_type: 1, level: 60, power2: 0, max_power2: 1_000, auras: []},
        player: %Player{},
        internal: %Internal{}
      }

      payload = %{outcome: :dodge, damage: 100, spell_id: nil, victim_guid: 77}
      entity = AttackFeedback.receive(entity, payload, nil, 1_000)

      assert entity.player.field_combo_target == 77
      assert entity.player.combo_points == 1
    end

    test "rogue builders grant points only after landing" do
      entity = rogue()
      spell = %Spell{id: 1757, effects: [%Effect{type: :add_combo_points, base_points: 0, die_sides: 1, base_dice: 1}]}

      landed = AttackFeedback.receive(entity, %{outcome: :normal, damage: 20, victim_guid: 77}, spell, 1_000)
      avoided = AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, victim_guid: 77}, spell, 1_000)

      assert landed.player.combo_points == 1
      assert avoided.player.combo_points in [nil, 0]
    end

    test "finishers consume points on hit but retain them on avoidance" do
      entity = Reactive.add_combo_points(rogue(), 77, 5)

      spell = %Spell{
        id: 6760,
        name: "Eviscerate",
        power_type: 3,
        mana_cost: 35,
        attributes: MapSet.new([:finishing_move])
      }

      landed = AttackFeedback.receive(entity, %{outcome: :normal, damage: 500, victim_guid: 77}, spell, 1_000)
      avoided = AttackFeedback.receive(entity, %{outcome: :parry, damage: 0, victim_guid: 77}, spell, 1_000)

      assert landed.player.combo_points == 0
      assert landed.player.field_combo_target == 77
      assert avoided.player.combo_points == 5
    end

    test "missed finishers retain points and refund eighty percent of their energy" do
      entity = rogue()
      entity = %{entity | unit: %{entity.unit | power4: 65}}
      entity = Reactive.add_combo_points(entity, 77, 5)

      spell = %Spell{
        id: 6760,
        name: "Eviscerate",
        power_type: 3,
        mana_cost: 35,
        attributes: MapSet.new([:finishing_move])
      }

      entity = AttackFeedback.receive(entity, %{outcome: :miss, damage: 0, victim_guid: 77}, spell, 1_000)

      assert entity.player.combo_points == 5
      assert entity.unit.power4 == 93
    end

    test "blade flurry queues a secondary strike from landed damage" do
      blade_flurry = %Spell{
        id: 13_877,
        duration_ms: 15_000,
        spell_family: 8,
        family_flags_0: 0x40000000,
        proc_type_mask: 0x14,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_melee_haste, base_points: 20},
          %Effect{index: 1, type: :apply_aura, aura: :dummy, trigger_spell_id: 22_482}
        ]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, blade_flurry, 1_000)

      entity =
        AttackFeedback.receive(
          entity,
          %{outcome: :normal, damage: 91, proc_damage: 123, victim_guid: 77},
          nil,
          1_000
        )

      assert Enum.any?(
               entity.internal.events,
               &match?(%{type: :blade_flurry, target_guid: 77, damage: 123, spell_id: 22_482}, &1)
             )
    end

    test "blade flurry does not trigger from avoided attacks" do
      blade_flurry = %Spell{
        id: 13_877,
        spell_family: 8,
        family_flags_0: 0x40000000,
        proc_type_mask: 0x14,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_melee_haste}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, blade_flurry, 1_000)

      entity =
        AttackFeedback.receive(entity, %{outcome: :dodge, damage: 123, proc_damage: 0, victim_guid: 77}, nil, 1_000)

      refute Enum.any?(entity.internal.events, &(&1.type == :blade_flurry))
    end

    test "sweeping strikes spends a charge and queues VMangos secondary damage" do
      sweeping_strikes = %Spell{
        id: 12_292,
        proc_type_mask: 0x14,
        proc_chance: 100,
        proc_charges: 5,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy}]
      }

      entity = %Mob{object: %Object{guid: 5}, unit: %Unit{auras: []}, internal: %Internal{}}
      {entity, _events} = Aura.apply_spell(entity, 5, 60, sweeping_strikes, 1_000)

      entity =
        AttackFeedback.receive(
          entity,
          %{outcome: :normal, damage: 91, proc_damage: 123, victim_guid: 77, spell_id: nil},
          nil,
          1_000
        )

      assert [%Holder{charges: 4}] = entity.unit.auras

      assert Enum.any?(
               entity.internal.events,
               &match?(
                 %{type: :secondary_melee, target_guid: 77, damage: 123, spell_id: 12_723, range_yards: 5.0},
                 &1
               )
             )
    end

    test "sweeping strikes does not chain from its triggered damage spell" do
      holder = %Holder{
        spell: %Spell{id: 12_292, proc_type_mask: 0x14, proc_chance: 100},
        caster_guid: 5,
        caster_level: 60,
        charges: 4,
        auras: [%AuraData{type: :dummy}]
      }

      entity = %Mob{object: %Object{guid: 5}, unit: %Unit{auras: [holder]}, internal: %Internal{}}

      entity =
        AttackFeedback.receive(
          entity,
          %{outcome: :normal, damage: 123, proc_damage: 123, victim_guid: 77, spell_id: 12_723},
          nil,
          1_000
        )

      assert [%Holder{charges: 4}] = entity.unit.auras
      refute Enum.any?(entity.internal.events || [], &(&1.type == :secondary_melee))
    end

    test "DBC melee proc auras trigger their encoded spell and spend charges" do
      proc_spell = %Spell{id: 19_577, proc_type_mask: 0x14, proc_chance: 100}

      holder = %Holder{
        spell: proc_spell,
        caster_guid: 5,
        caster_level: 60,
        charges: 1,
        auras: [%AuraData{type: :proc_trigger_spell, trigger_spell_id: 24_394}]
      }

      entity = rogue_with_auras([holder])
      result = AttackFeedback.receive(entity, %{outcome: :normal, damage: 20, victim_guid: 77}, nil, 1_000)

      assert result.unit.auras == []

      assert [%{type: :trigger_spell, source_guid: 5, target_guid: 77, spell_id: 24_394}] =
               result.internal.events
    end

    test "VMangos proc cooldown prevents another melee trigger until it expires" do
      proc_spell = %Spell{
        id: 16_864,
        proc_type_mask: 0x14,
        proc_chance: 100,
        proc_rule: %ProcRule{cooldown_ms: 10_000}
      }

      holder = %Holder{
        spell: proc_spell,
        caster_guid: 5,
        caster_level: 60,
        slot: 0,
        auras: [%AuraData{type: :proc_trigger_spell, trigger_spell_id: 16_870}]
      }

      entity = rogue_with_auras([holder])
      first = AttackFeedback.receive(entity, %{outcome: :normal, damage: 20, victim_guid: 77}, nil, 1_000)
      [updated_holder] = first.unit.auras

      assert updated_holder.next_proc_at == 11_000
      assert [%{spell_id: 16_870}] = first.internal.events

      first = %{first | internal: %{first.internal | events: []}}
      second = AttackFeedback.receive(first, %{outcome: :normal, damage: 20, victim_guid: 77}, nil, 2_000)

      assert second.internal.events == []
      assert [^updated_holder] = second.unit.auras
    end
  end

  defp rogue do
    rogue_with_auras([])
  end

  defp rogue_with_auras(auras) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: 4,
        level: 60,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        base_attack_time: 2_000,
        auras: auras
      },
      player: %Player{},
      internal: %Internal{blackboard: %Blackboard{auto_attacking: true, attack_started: true}}
    }
  end
end
