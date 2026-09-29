defmodule ThistleTea.Game.World.Loader.SpellCorpseTargetDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "retains corpse targeting and separate caster rewards for quest tools" do
      for id <- [10_617, 11_885, 11_886, 11_887, 11_888, 11_889] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :allow_dead_target)
        assert [%Effect{type: :dummy}, %Effect{implicit_target_a: :caster}] = spell.effects
      end

      refute Spell.attribute?(SpellLoader.load(133), :allow_dead_target)
      refute Spell.attribute?(SpellLoader.load(2050), :allow_dead_target)
    end
  end
end
