defmodule ThistleTea.Game.World.Loader.SpellAutoRepeatDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "recognizes wand Shoot and Auto Shot while keeping Throw manual" do
      wand = SpellLoader.load(5019)
      bow = SpellLoader.load(75)
      assert Spell.auto_repeat?(wand)
      assert Spell.wand?(wand)
      assert wand.dmg_class == 1
      assert Spell.ranged_attack?(wand)
      assert Spell.auto_repeat?(bow)
      refute Spell.wand?(bow)
      refute Spell.auto_repeat?(SpellLoader.load(2764))
    end
  end
end
