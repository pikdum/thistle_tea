defmodule ThistleTea.Game.World.Loader.PickpocketDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.Pickpocket
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Pick Pocket keeps stealth on success and provokes its target on failure" do
      spell = SpellLoader.load(921)
      assert Pickpocket.spell?(spell)
      assert Spell.attribute?(spell, :allow_while_stealthed)
      assert Spell.attribute?(spell, :failure_breaks_stealth)
      assert Spell.attribute?(spell, :threat_only_on_miss)
      assert Spell.harmful?(spell)
      refute Spell.starts_combat?(spell)
      assert Spell.starts_combat?(spell, :miss)
      assert spell.range_yards == 5.0
    end
  end
end
