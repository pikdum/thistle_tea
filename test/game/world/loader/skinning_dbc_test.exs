defmodule ThistleTea.Game.World.Loader.SkinningDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.Skinning
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads all profession ranks as nonharmful corpse interactions" do
      for id <- [8613, 8617, 8618, 10_768] do
        spell = SpellLoader.load(id)
        assert Skinning.spell?(spell)
        refute Spell.harmful?(spell)
        assert [%{type: :skinning, implicit_target_a: :any_unit} | _] = spell.effects
        assert spell.cast_time_ms > 0
        assert spell.range_yards == 5.0
      end
    end
  end
end
