defmodule ThistleTea.Game.World.Loader.SpellHonorDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "decodes honor rewards with their unscaled DBC amounts" do
      for {id, points} <- [{31_415, 25}, {24_960, 50}, {24_965, 398}, {24_966, 2388}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.type == :honor))
        assert %Semantics.Honor{} = effect.semantic
        assert Effect.roll(effect, 0) == points
      end
    end

    test "Warsong match reward spells create marks without duplicating bonus honor" do
      for id <- [24_950, 24_951] do
        spell = SpellLoader.load(id)
        refute Enum.any?(spell.effects, &(&1.type == :honor))
      end
    end
  end
end
