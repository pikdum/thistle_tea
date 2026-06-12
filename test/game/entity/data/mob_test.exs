defmodule ThistleTea.Game.Entity.Data.MobTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "build/1" do
    test "stores creature movement speeds as actual speeds" do
      creature =
        %Mangos.Creature{
          guid: 1,
          id: 2,
          modelid: 3,
          curhealth: 10,
          creature_movement: [],
          creature_template: %Mangos.CreatureTemplate{
            entry: 2,
            name: "Test Creature",
            speed_walk: 1.2,
            speed_run: 1.5,
            min_level: 1,
            max_level: 1,
            scale: 1.0
          }
        }
        |> Map.put(:creature_model_info, nil)
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.movement_block.update_flag == 0x70
      assert mob.movement_block.walk_speed == 3.0
      assert mob.movement_block.run_speed == 10.5
      assert mob.movement_block.run_back_speed == 6.75
      assert_in_delta mob.movement_block.swim_speed, 7.083333, 0.000001
      assert mob.movement_block.swim_back_speed == 3.75
    end

    test "stores XP reward metadata from creature templates" do
      creature =
        %Mangos.Creature{
          guid: 1,
          id: 2,
          modelid: 3,
          curhealth: 10,
          creature_movement: [],
          creature_template: %Mangos.CreatureTemplate{
            entry: 2,
            name: "Test Creature",
            min_level: 1,
            max_level: 1,
            scale: 1.0,
            speed_walk: 1.0,
            speed_run: 1.0,
            experience_multiplier: 1.5,
            extra_flags: 0x40,
            rank: 1
          }
        }
        |> Map.put(:creature_model_info, nil)
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.internal.creature.experience_multiplier == 1.5
      assert mob.internal.creature.extra_flags == 0x40
      assert mob.internal.creature.rank == 1
      assert mob.internal.spawn.respawn_delay_ms == 120_000
      assert mob.internal.spawn.unit == mob.unit
      assert mob.internal.spawn.movement_block == mob.movement_block
    end

    test "stores respawn delay from creature spawn time" do
      creature =
        %Mangos.Creature{
          guid: 1,
          id: 2,
          modelid: 3,
          curhealth: 10,
          spawntimesecs: 7,
          creature_movement: [],
          creature_template: %Mangos.CreatureTemplate{
            entry: 2,
            name: "Test Creature",
            speed_walk: 1.0,
            speed_run: 1.0,
            min_level: 1,
            max_level: 1,
            scale: 1.0
          }
        }
        |> Map.put(:creature_model_info, nil)
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.internal.spawn.respawn_delay_ms == 7_000
    end
  end

  describe "respawn/1" do
    test "restores the mob from spawn state" do
      spawn_unit = %Unit{health: 10, max_health: 10, power1: 4, max_power1: 4, level: 2}
      spawn_movement_block = %MovementBlock{position: {1.0, 2.0, 3.0, 4.0}, movement_flags: 0}

      mob = %Mob{
        unit: %{spawn_unit | health: 0, power1: 0, target: Guid.from_low_guid(:player, 1)},
        movement_block: %{spawn_movement_block | position: {9.0, 9.0, 9.0, 0.0}, movement_flags: 1},
        internal: %Internal{
          in_combat: true,
          last_hostile_time: 123,
          running: true,
          movement_start_time: 456,
          movement_start_position: {9.0, 9.0, 9.0},
          spawn: %Spawn{
            unit: spawn_unit,
            movement_block: spawn_movement_block,
            respawn_ref: make_ref()
          }
        }
      }

      mob = Mob.respawn(mob)

      assert mob.unit == spawn_unit
      assert mob.movement_block == spawn_movement_block
      refute mob.internal.in_combat
      refute mob.internal.running
      assert mob.internal.last_hostile_time == nil
      assert mob.internal.movement_start_time == nil
      assert mob.internal.movement_start_position == nil
      assert mob.internal.spawn.respawn_ref == nil
    end
  end

  describe "handle_cast/2" do
    test "rewards a player when their attack kills the mob" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      mob_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive]))

      Entity.register(player_guid)

      on_exit(fn ->
        Entity.unregister(player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        unit: %Unit{health: 1, max_health: 1, level: 1},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          map: 0,
          creature: %Creature{experience_multiplier: 1.0, extra_flags: 0, rank: 0},
          spawn: %Spawn{},
          loot: %Loot{}
        }
      }

      assert {:noreply, %Mob{unit: %Unit{health: 0}}, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_attack, %{caster: player_guid, damage: 1}}, mob)

      assert_receive {:"$gen_cast", {:reward_kill, %Mob{object: %Object{guid: ^mob_guid}}}}
    end

    test "schedules respawn when a mob dies" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      mob_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive]))

      Entity.register(player_guid)

      on_exit(fn ->
        Entity.unregister(player_guid)
      end)

      mob = %Mob{
        object: %Object{guid: mob_guid},
        unit: %Unit{health: 1, max_health: 1, level: 1},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          map: 0,
          creature: %Creature{experience_multiplier: 1.0, extra_flags: 0, rank: 0},
          spawn: %Spawn{respawn_delay_ms: 1},
          loot: %Loot{}
        }
      }

      assert {:noreply, %Mob{internal: %Internal{spawn: %Spawn{respawn_ref: ref}}}, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_attack, %{caster: player_guid, damage: 1}}, mob)

      assert is_reference(ref)
      assert_receive :respawn
    end
  end

  describe "handle_info/2" do
    test "respawns a dead mob in place" do
      mob_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive]))
      spawn_unit = %Unit{health: 10, max_health: 10, power1: 4, max_power1: 4, level: 2}
      spawn_movement_block = %MovementBlock{position: {1.0, 2.0, 3.0, 4.0}, movement_flags: 0}

      mob = %Mob{
        object: %Object{guid: mob_guid},
        unit: %{spawn_unit | health: 0, power1: 0},
        movement_block: %{spawn_movement_block | position: {9.0, 9.0, 9.0, 0.0}, movement_flags: 1},
        internal: %Internal{
          map: 0,
          name: "Test Creature",
          in_combat: true,
          creature: %Creature{},
          spawn: %Spawn{
            unit: spawn_unit,
            movement_block: spawn_movement_block,
            respawn_ref: make_ref()
          },
          loot: %Loot{}
        }
      }

      on_exit(fn ->
        SpatialHash.remove(:mobs, mob_guid)
        Metadata.delete(mob_guid)
      end)

      assert {:noreply, %Mob{} = respawned} = MobServer.handle_info(:respawn, mob)

      assert respawned.object.guid == mob_guid
      assert respawned.unit == spawn_unit
      assert respawned.movement_block == spawn_movement_block
      assert respawned.internal.spawn.respawn_ref == nil
      assert SpatialHash.get_entity(mob_guid) == {mob_guid, 0, 1.0, 2.0, 3.0}
      assert %{alive?: true, level: 2} = Metadata.get(mob_guid)
    end
  end
end
