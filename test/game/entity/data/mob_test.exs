defmodule ThistleTea.Game.Entity.Data.MobTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob

  describe "build/1" do
    test "stores creature movement speeds as actual speeds" do
      creature = %Mangos.Creature{
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

      mob = Mob.build(creature)

      assert mob.movement_block.walk_speed == 3.0
      assert mob.movement_block.run_speed == 10.5
      assert mob.movement_block.run_back_speed == 6.75
      assert_in_delta mob.movement_block.swim_speed, 7.083333, 0.000001
      assert mob.movement_block.swim_back_speed == 3.75
    end
  end
end
