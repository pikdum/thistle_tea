defmodule ThistleTea.Game.Entity.Logic.AI.BT.CombatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "melee_attack/3" do
    test "queues attack delivery events instead of dispatching directly" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: true, next_attack_at: 0}

      assert {:success, mob, %Blackboard{}} = Combat.melee_attack(mob, blackboard, 1_000)

      assert [
               %Event{
                 type: :deliver_attack,
                 target_guid: ^target_guid,
                 attack: %{caster: 1, min_damage: 3, max_damage: 3, damage: 3}
               }
             ] = mob.internal.events
    end

    test "queues independent main-hand and off-hand swings for dual wielders" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 10,
          max_damage: 10,
          min_offhand_damage: 8,
          max_offhand_damage: 8,
          combat_reach: 1.0,
          base_attack_time: 2_000,
          offhand_attack_time: 1_500
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: true, next_attack_at: 0, next_offhand_attack_at: 0}
      assert {:success, mob, blackboard} = Combat.melee_attack(mob, blackboard, 1_000)

      attacks = Enum.filter(mob.internal.events, &(&1.type == :deliver_attack))
      assert length(attacks) == 2
      assert Enum.any?(attacks, &(Map.get(&1.attack, :offhand?) == true and &1.attack.damage == 4))
      assert blackboard.next_attack_at == 3_000
      assert blackboard.next_offhand_attack_at == 2_500
    end

    test "sends queued melee spell go before delivering the attack" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      spell = %Spell{id: 78}

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true, next_swing_spell: spell},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: true, next_attack_at: 0}

      assert {:success, mob, %Blackboard{}} = Combat.melee_attack(mob, blackboard, 1_000)

      assert [
               %Event{type: :spell_cast_result, spell_id: 78},
               %Event{type: :spell_go, spell_id: 78, hit_guids: [^target_guid]},
               %Event{type: :deliver_spell, target_guid: ^target_guid, spell: %Spell{id: 78}}
             ] = mob.internal.events

      assert mob.internal.next_swing_spell == nil
    end

    test "swings immediately on fresh aggro when already in reach" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 2_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: false, next_attack_at: 0}

      assert {:success, mob, %Blackboard{attack_started: true, next_attack_at: 3_000}} =
               Combat.melee_attack(mob, blackboard, 1_000)

      assert Enum.any?(mob.internal.events, &(&1.type == :deliver_attack))
    end

    test "retries shortly instead of arming a full swing timer when out of reach on fresh aggro" do
      target_guid = 2
      SpatialHash.update(:players, target_guid, 0, 50.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:players, target_guid) end)

      mob = %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          target: target_guid,
          min_damage: 3,
          max_damage: 3,
          combat_reach: 1.0,
          base_attack_time: 2_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: false, next_attack_at: 0}

      assert {:success, mob, %Blackboard{attack_started: true, next_attack_at: 1_100}} =
               Combat.melee_attack(mob, blackboard, 1_000)

      refute Enum.any?(mob.internal.events, &(&1.type == :deliver_attack))
    end

    test "grants no rage at swing time since rage flows from resolved outcomes" do
      player_guid = Guid.from_low_guid(:player, 1)
      target_guid = Guid.from_low_guid(:mob, 1, 1)

      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)
      on_exit(fn -> SpatialHash.remove(:mobs, target_guid) end)

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{
          target: target_guid,
          min_damage: 10,
          max_damage: 10,
          combat_reach: 1.0,
          base_attack_time: 1_000,
          power_type: 1,
          power2: 0,
          max_power2: 1_000
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: true, next_attack_at: 0}

      assert {:success, character, %Blackboard{}} = Combat.melee_attack(character, blackboard, 1_000)

      assert character.unit.power2 == 0

      assert [
               %Event{type: :deliver_attack, target_guid: ^target_guid, attack: %{damage: 10}}
             ] = Enum.filter(character.internal.events, &(&1.type == :deliver_attack))
    end
  end

  describe "wait_for_next_attack/3" do
    test "returns running delay from explicit time" do
      blackboard = %Blackboard{next_attack_at: 1_250}
      state = %Mob{}

      assert {{:running, 250}, ^state, ^blackboard} = Combat.wait_for_next_attack(state, blackboard, 1_000)
    end
  end

  describe "in_combat?/2" do
    test "a player qualifies on auto-attack intent even before the combat flag is set" do
      character = %Character{unit: %Unit{target: 2}, internal: %Internal{in_combat: false}}

      assert Combat.in_combat?(character, %Blackboard{auto_attacking: true})
    end

    test "a player without auto-attack intent does not qualify even while flagged in combat" do
      character = %Character{unit: %Unit{target: 2}, internal: %Internal{in_combat: true}}

      refute Combat.in_combat?(character, %Blackboard{auto_attacking: false})
    end

    test "a mob still requires the in-combat flag, not just intent" do
      not_engaged = %Mob{unit: %Unit{target: 2}, internal: %Internal{in_combat: false}}
      engaged = %Mob{unit: %Unit{target: 2}, internal: %Internal{in_combat: true}}

      refute Combat.in_combat?(not_engaged, %Blackboard{auto_attacking: true})
      assert Combat.in_combat?(engaged, %Blackboard{})
    end
  end
end
