defmodule ThistleTea.Game.World.Loader.SpellResurrectionDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "only Rebirth bypasses the corpse recovery timer" do
      for id <- [20_484, 20_739, 20_742, 20_747, 20_748] do
        assert Spell.attribute?(SpellLoader.load(id), :no_resurrection_timer)
      end

      for id <- [2006, 2008, 7328, 8342] do
        refute Spell.attribute?(SpellLoader.load(id), :no_resurrection_timer)
      end
    end
  end
end
