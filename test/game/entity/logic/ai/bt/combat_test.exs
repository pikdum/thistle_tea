defmodule ThistleTea.Game.Entity.Logic.AI.BT.CombatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.SpatialHash

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
        internal: %Internal{map: 0, in_combat: true},
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

    test "generates rage for player auto attacks" do
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
        internal: %Internal{map: 0, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      blackboard = %Blackboard{attack_started: true, next_attack_at: 0}

      assert {:success, character, %Blackboard{}} = Combat.melee_attack(character, blackboard, 1_000)

      assert character.unit.power2 == 100

      assert [
               %Event{type: :object_update, update_type: :values},
               %Event{type: :deliver_attack, target_guid: ^target_guid, attack: %{damage: 10}}
             ] = character.internal.events
    end
  end

  describe "wait_for_next_attack/3" do
    test "returns running delay from explicit time" do
      blackboard = %Blackboard{next_attack_at: 1_250}
      state = %Mob{}

      assert {{:running, 250}, ^state, ^blackboard} = Combat.wait_for_next_attack(state, blackboard, 1_000)
    end
  end
end
