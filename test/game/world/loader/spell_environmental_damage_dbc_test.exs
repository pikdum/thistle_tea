defmodule ThistleTea.Game.World.Loader.SpellEnvironmentalDamageDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads all environmental fire spells without combat initiation" do
      for id <- [7897, 7902, 12_796, 20_533, 20_676, 21_650, 23_485, 29_115] do
        spell = SpellLoader.load(id)
        assert spell.school == :fire

        assert [%{type: :environmental_damage, semantic: %Semantics.DamageHeal{kind: :environmental_damage}}] =
                 spell.effects

        assert Spell.harmful?(spell)
        refute Spell.starts_combat?(spell)
        refute Spell.starts_combat?(spell, :miss)
      end
    end
  end
end
