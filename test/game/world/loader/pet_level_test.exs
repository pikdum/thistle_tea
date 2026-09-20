defmodule ThistleTea.Game.World.Loader.PetLevelTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.World.Loader.PetLevel, as: PetLevelLoader

  @moduletag :vmangos_db

  describe "load_all/1" do
    test "translates the complete vanilla hunter growth and XP catalogue" do
      table = :ets.new(__MODULE__, [:set])
      assert :ok = PetLevelLoader.load_all(table)
      levels = PetLevelLoader.levels(table)
      assert %PetLevel{health: 156, armor: 322, next_level_xp: 1_350} = levels[8]
      assert %PetLevel{health: 2_215, next_level_xp: 36_875} = levels[50]
      assert %PetLevel{health: 3_052} = levels[60]
      assert Enum.all?(1..60, &(levels[&1].next_level_xp > 0))
    end
  end
end
