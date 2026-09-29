defmodule ThistleTea.Game.World.Loader.SpellResurrectionDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "class resurrection spells use flat health while jumper cables use player-only percentages" do
      for {id, health, mana} <- [{2006, 70, 135}, {2008, 65, 120}, {7328, 65, 120}, {20_484, 400, 700}] do
        assert [%Effect{type: :resurrect_new, misc_value: ^mana} = effect] = SpellLoader.load(id).effects
        assert Effect.roll(effect, 0) == health
      end

      assert [%Effect{type: :resurrect}] = SpellLoader.load(8342).effects
    end

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
