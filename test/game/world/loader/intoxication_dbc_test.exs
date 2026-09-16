defmodule ThistleTea.Game.World.Loader.IntoxicationDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads alcohol strengths and Sober Up as supported resource effects" do
      for {id, amount} <- [{11_007, 5}, {11_008, 10}, {11_009, 20}, {11_629, 50}, {16_712, 100}, {24_635, -1000}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.type == :inebriate))
        assert %Effect{} = effect
        assert Effect.roll(effect, 0) == amount
        assert %Semantics.Resource{kind: :inebriate} = Semantics.effect_rule(effect)
      end
    end
  end
end
