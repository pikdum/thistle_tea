defmodule ThistleTea.Game.Entity.Logic.CombatTest do
  use ExUnit.Case, async: true

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
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "attack_start/2" do
    test "returns an attack_start event" do
      assert %Event{type: :attack_start, source_guid: 1, target_guid: 2} = Combat.attack_start(1, 2)
    end
  end

  describe "attacker_state_update/4" do
    test "returns an attacker_state_update event with attack details" do
      event = Combat.attacker_state_update(1, 2, 12, %{spell_id: 99})

      assert %Event{
               type: :attacker_state_update,
               source_guid: 1,
               target_guid: 2,
               damage: 12,
               attack: %{spell_id: 99}
             } = event
    end
  end

  describe "melee_reach/2" do
    test "sums combat reaches plus the base melee offset" do
      assert_in_delta Combat.melee_reach(2.0, 3.0), 6.333, 0.0001
    end

    test "floors at the attack distance for small combatants" do
      assert Combat.melee_reach(1.5, 1.5) == 5.0
    end
  end

  describe "chase_target_distance/1" do
    test "is the melee reach pulled just inside its outer edge" do
      assert Combat.chase_target_distance(5.0) == 4.5
    end
  end

  describe "chase_rechase_distance/2" do
    test "is three quarters of the melee reach minus the target bounding radius" do
      assert_in_delta Combat.chase_rechase_distance(6.0, 1.0), 3.5, 0.0001
    end

    test "never goes negative" do
      assert Combat.chase_rechase_distance(1.0, 5.0) == 0.0
    end
  end

  describe "damage_range/1" do
    test "scales creature melee by damage multiplier only" do
      mob = %Mob{
        unit: %Unit{min_damage: 10.0, max_damage: 20.0, attack_power: 70, base_attack_time: 2_000},
        internal: %Internal{creature: %Creature{damage_multiplier: 1.5}}
      }

      {min_damage, max_damage} = Combat.damage_range(mob)

      assert min_damage == 15.0
      assert max_damage == 30.0
    end

    test "leaves non-creature damage ranges unchanged" do
      entity = %{unit: %Unit{min_damage: 10.0, max_damage: 20.0, attack_power: 70, base_attack_time: 2_000}}

      assert Combat.damage_range(entity) == {10.0, 20.0}
    end
  end

  describe "sync_combat_flag/1" do
    @unit_flag_in_combat 0x00080000

    test "sets the combat flag and marks a broadcast when entering combat" do
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{flags: 0}, internal: %Internal{in_combat: true}}

      mob = Combat.sync_combat_flag(mob)

      assert Bitwise.band(mob.unit.flags, @unit_flag_in_combat) == @unit_flag_in_combat
      assert mob.internal.broadcast_update? == true
    end

    test "clears the combat flag when combat drops" do
      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{flags: @unit_flag_in_combat},
        internal: %Internal{in_combat: false}
      }

      mob = Combat.sync_combat_flag(mob)

      assert Bitwise.band(mob.unit.flags, @unit_flag_in_combat) == 0
      assert mob.internal.broadcast_update? == true
    end

    test "leaves consistent flags untouched" do
      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{flags: @unit_flag_in_combat},
        internal: %Internal{in_combat: true}
      }

      assert Combat.sync_combat_flag(mob) == mob
    end
  end

  describe "receive_attack/4" do
    test "applies damage and returns attacker update events" do
      mob = mob(2, 100)

      {mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000, roll: 9_999)

      assert mob.unit.health == 88
      assert mob.internal.broadcast_update? == true

      assert [
               %Event{
                 type: :attacker_state_update,
                 source_guid: 1,
                 target_guid: 2,
                 damage: 12,
                 attack: %{hit_info: 0x2, damage_state: 1, blocked_amount: 0, absorb: 0}
               },
               %Event{
                 type: :attack_outcome,
                 target_guid: 1,
                 source_guid: 2,
                 outcome: :normal,
                 damage: 12,
                 spell_id: nil
               }
             ] = events
    end

    test "includes hit reaction events while target survives" do
      spell = damage_shield_spell()
      {mob, _events} = Aura.apply_spell(mob(2, 100), 2, 10, spell, 1_000)

      {_mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000, roll: 9_999)

      assert [
               %Event{type: :attacker_state_update},
               %Event{
                 type: :trigger_spell,
                 source_guid: 2,
                 source_level: 10,
                 target_guid: 1,
                 spell_id: 6136
               },
               %Event{type: :attack_outcome}
             ] = events
    end

    test "retaliation counterattacks attackers in front and spends a charge" do
      retaliation = %Spell{
        id: 20_230,
        proc_type_mask: 0x28,
        proc_chance: 100,
        proc_charges: 30,
        effects: [%Effect{type: :apply_aura, aura: :dummy}]
      }

      target = %{mob(2, 100) | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}}
      {target, _events} = Aura.apply_spell(target, 2, 60, retaliation, 1_000)

      {target, events} =
        Combat.receive_attack(
          target,
          %{caster: 1, caster_position: {1.0, 0.0, 0.0}, damage: 12},
          1_000,
          roll: 9_999
        )

      assert [%Holder{charges: 29}] = target.unit.auras

      assert Enum.any?(
               events,
               &match?(%Event{type: :trigger_spell, source_guid: 2, target_guid: 1, spell_id: 22_858}, &1)
             )
    end

    test "retaliation does not counterattack from behind" do
      retaliation = %Spell{
        id: 20_230,
        proc_type_mask: 0x28,
        proc_chance: 100,
        proc_charges: 30,
        effects: [%Effect{type: :apply_aura, aura: :dummy}]
      }

      target = %{mob(2, 100) | movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}}
      {target, _events} = Aura.apply_spell(target, 2, 60, retaliation, 1_000)

      {target, events} =
        Combat.receive_attack(
          target,
          %{caster: 1, caster_position: {-1.0, 0.0, 0.0}, damage: 12},
          1_000,
          roll: 9_999
        )

      assert [%Holder{charges: 30}] = target.unit.auras
      refute Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 22_858))
    end

    test "does not include hit reaction events when target dies" do
      spell = damage_shield_spell()
      {mob, _events} = Aura.apply_spell(mob(2, 10), 2, 10, spell, 1_000)

      {_mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000, roll: 9_999)

      assert [%Event{type: :attacker_state_update}, %Event{type: :attack_outcome}] = events
    end

    test "dodged attacks deal no damage and skip hit reactions" do
      spell = damage_shield_spell()
      {mob, _events} = Aura.apply_spell(mob(2, 100, 10), 2, 10, spell, 1_000)
      attack = %{caster: 1, damage: 12, caster_level: 10}

      {mob, events} = Combat.receive_attack(mob, attack, 1_000, roll: 500)

      assert mob.unit.health == 100

      assert [
               %Event{
                 type: :attacker_state_update,
                 damage: 0,
                 attack: %{damage_state: 2, hit_info: 0x2}
               },
               %Event{type: :attack_outcome, outcome: :dodge, damage: 12}
             ] = events
    end

    test "rage-using players gain rage from damage taken" do
      character = %Character{
        object: %Object{guid: 5},
        unit: %Unit{
          health: 500,
          max_health: 500,
          level: 60,
          power_type: 1,
          power2: 0,
          max_power2: 1_000,
          auras: []
        },
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      attack = %{caster: 1, damage: 200, caster_level: 60}
      opts = [roll: 9_999, skill_roll: fn _chance -> false end]

      {character, _events} = Combat.receive_attack(character, attack, 1_000, opts)

      assert character.unit.health == 300
      assert character.unit.power2 == 21
    end

    test "missed attacks report the miss hit info" do
      mob = mob(2, 100, 10)

      {mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12, caster_level: 10}, 1_000, roll: 0)

      assert mob.unit.health == 100

      assert [
               %Event{type: :attacker_state_update, damage: 0, attack: %{hit_info: 0x12, damage_state: 0}},
               %Event{type: :attack_outcome, outcome: :miss, damage: 0}
             ] = events
    end
  end

  describe "Event queue" do
    test "enqueues and drains pending events from internal state" do
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}
      event = Combat.attack_start(1, 2)

      mob = Event.enqueue(mob, event)
      assert {mob, [^event]} = Event.drain(mob)
      assert mob.internal.events == []
    end
  end

  defp mob(guid, health, level \\ nil) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: health, level: level, auras: []},
      internal: %Internal{}
    }
  end

  defp damage_shield_spell do
    %Spell{
      id: 168,
      effects: [
        %Effect{
          type: :apply_aura,
          aura: :damage_shield,
          trigger_spell_id: 6136
        }
      ]
    }
  end
end
