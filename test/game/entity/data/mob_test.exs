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
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
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
            rank: 1,
            damage_multiplier: 2.5
          }
        }
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.internal.creature.experience_multiplier == 1.5
      assert mob.internal.creature.extra_flags == 0x40
      assert mob.internal.creature.rank == 1
      assert mob.internal.creature.damage_multiplier == 2.5
      assert mob.internal.spawn.respawn_delay_ms == 120_000
      assert mob.internal.spawn.unit == mob.unit
      assert mob.internal.spawn.movement_block == mob.movement_block
    end

    test "keeps class-level max health untouched by a later stat recompute" do
      creature =
        %Mangos.Creature{
          guid: 1,
          id: 2,
          modelid: 3,
          creature_movement: [],
          creature_template: %Mangos.CreatureTemplate{
            entry: 2,
            name: "Test Creature",
            speed_walk: 1.0,
            speed_run: 1.0,
            min_level: 60,
            max_level: 60,
            scale: 1.0,
            health_multiplier: 1.0,
            mana_multiplier: 1.0
          }
        }
        |> Map.put(:equip_items, [nil, nil, nil])
        |> Map.put(:creature_class_level_stats, %Mangos.CreatureClassLevelStats{
          class: 1,
          level: 60,
          health: 3052,
          base_health: 1689,
          mana: 0,
          base_mana: 0,
          melee_damage: 100.0,
          ranged_damage: 0.0,
          stamina: 256
        })

      mob = Mob.build(creature)

      assert mob.unit.max_health == 3052
      assert mob.unit.health == 3052
      assert mob.unit.base_health == nil

      assert Stats.recompute(mob.unit) == mob.unit
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
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.internal.spawn.respawn_delay_ms == 7_000
    end
  end

  describe "apply_addon_auras/2" do
    test "build applies addon auras to the unit but not the spawn snapshot" do
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
            speed_walk: 1.0,
            speed_run: 1.0,
            min_level: 5,
            max_level: 5,
            scale: 1.0
          }
        }
        |> Map.put(:equip_items, [nil, nil, nil])
        |> Map.put(:addon_auras, [frost_armor()])

      mob = Mob.build(creature)

      assert [%{spell: %{id: 12_544}}] = mob.unit.auras
      assert mob.internal.creature.addon_auras == [frost_armor()]
      assert mob.internal.spawn.unit.auras == []
    end

    test "reapplies addon auras with fresh timestamps" do
      spawn_unit = %Unit{health: 10, max_health: 10, level: 2, auras: []}

      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 2, 1)},
        unit: spawn_unit,
        internal: %Internal{
          creature: %Creature{addon_auras: [frost_armor()]},
          spawn: %Spawn{unit: spawn_unit}
        }
      }

      mob = mob |> Mob.respawn() |> Mob.apply_addon_auras(999_000)

      assert [%{spell: %{id: 12_544}, applied_at: 999_000}] = mob.unit.auras
    end
  end

  defp frost_armor do
    %Spell{
      id: 12_544,
      name: "Frost Armor",
      school: :frost,
      cast_time_ms: 0,
      duration_ms: 1_800_000,
      attributes: MapSet.new(),
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: :mod_resistance,
          base_points: 29,
          die_sides: 1,
          misc_value: 16
        }
      ]
    }
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

      assert {:noreply, %Mob{unit: %Unit{health: 0}} = mob, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_attack, %{caster: player_guid, damage: 1, caster_level: 99}}, mob)

      assert {:noreply, %Mob{}} = MobServer.handle_continue(:maybe_broadcast, mob)

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

      assert {:noreply, %Mob{} = mob, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_attack, %{caster: player_guid, damage: 1, caster_level: 99}}, mob)

      assert {:noreply, %Mob{internal: %Internal{spawn: %Spawn{respawn_ref: ref}}}} =
               MobServer.handle_continue(:maybe_broadcast, mob)

      assert is_reference(ref)
      assert_receive :respawn
    end
  end

  describe "handle_continue/2" do
    test "finalizes a death that did not arrive through an attack" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      mob_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive]))

      Entity.register(player_guid)
      on_exit(fn -> Entity.unregister(player_guid) end)

      dead_mob = dead_mob(mob_guid, killed_by: player_guid, death_finalized?: false)

      assert {:noreply, %Mob{internal: %Internal{spawn: %Spawn{respawn_ref: ref}, death_finalized?: true}}} =
               MobServer.handle_continue(:maybe_broadcast, dead_mob)

      assert is_reference(ref)
      assert_receive {:"$gen_cast", {:reward_kill, %Mob{object: %Object{guid: ^mob_guid}}}}
      assert_receive :respawn
    end

    test "does not finalize an already-finalized death again" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      mob_guid = Guid.from_low_guid(:mob, 2, System.unique_integer([:positive]))

      Entity.register(player_guid)
      on_exit(fn -> Entity.unregister(player_guid) end)

      dead_mob = dead_mob(mob_guid, killed_by: player_guid, death_finalized?: true)

      assert {:noreply, %Mob{}} = MobServer.handle_continue(:maybe_broadcast, dead_mob)

      refute_receive {:"$gen_cast", {:reward_kill, _}}
    end
  end

  defp dead_mob(mob_guid, opts) do
    %Mob{
      object: %Object{guid: mob_guid},
      unit: %Unit{health: 0, max_health: 1, level: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        map: 0,
        creature: %Creature{experience_multiplier: 1.0, extra_flags: 0, rank: 0},
        spawn: %Spawn{respawn_delay_ms: 1},
        loot: %Loot{},
        broadcast_update?: true,
        killed_by: Keyword.get(opts, :killed_by),
        death_finalized?: Keyword.get(opts, :death_finalized?, false)
      }
    }
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
