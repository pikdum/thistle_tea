defmodule ThistleTea.Game.World.Loader.SpellChainDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "retains chain lightning and chain heal jump counts and attenuation" do
      for {id, target, multiplier} <- [{421, :target_enemy, 0.7}, {1064, :chain_heal, 0.5}] do
        spell = SpellLoader.load(id)
        effect = hd(spell.effects)
        assert effect.chain_targets == 3
        assert effect.implicit_target_a == target
        assert_in_delta effect.damage_multiplier, multiplier, 0.0001
        assert Spell.requires_friendly_target?(spell) == (target == :chain_heal)
      end
    end
  end
end
