defmodule ThistleTea.Game.Entity.Data.MobTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid

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
            experience_multiplier: 1.5,
            extra_flags: 0x40,
            rank: 1
          }
        }
        |> Map.put(:creature_model_info, nil)
        |> Map.put(:equip_items, [nil, nil, nil])

      mob = Mob.build(creature)

      assert mob.internal.experience_multiplier == 1.5
      assert mob.internal.extra_flags == 0x40
      assert mob.internal.rank == 1
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
        internal: %Internal{map: 0, experience_multiplier: 1.0, extra_flags: 0, rank: 0}
      }

      assert {:noreply, %Mob{unit: %Unit{health: 0}}, {:continue, :maybe_broadcast}} =
               MobServer.handle_cast({:receive_attack, %{caster: player_guid, damage: 1}}, mob)

      assert_receive {:"$gen_cast", {:reward_kill, %Mob{object: %Object{guid: ^mob_guid}}}}
    end
  end
end
