defmodule ThistleTea.Game.World.Loader.SpellDisenchantDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads the three-second item disenchant effect" do
      spell = SpellLoader.load(13_262)
      assert spell.name == "Disenchant"
      assert spell.cast_time_ms == 3_000
      assert [%{type: :disenchant, semantic: %Semantics.Inventory{kind: :disenchant}}] = spell.effects
      ability = DBC.get(SkillLineAbility, 7316)
      assert ability.spell == spell.id
      assert ability.skill_line == 333
      assert ability.trivial_skill_line_rank_low == 20
      assert ability.trivial_skill_line_rank_high == 60
    end
  end
end
