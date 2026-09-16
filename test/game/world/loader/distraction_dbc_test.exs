defmodule ThistleTea.Game.World.Loader.DistractionDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "build_spellbook/1" do
    test "loads vanilla Distract as a stealth-preserving ground spell" do
      spell = SpellLoader.build_spellbook([1725])[1725]
      assert [%Effect{type: :distract} = effect] = Enum.reject(spell.effects, &(&1.type == :none))
      assert Effect.roll(effect, 0) == 10
      assert Spell.attribute?(spell, :allow_while_stealthed)
      assert Spell.harmful?(spell)
      refute Spell.starts_combat?(spell)
      assert {:targeted_aoe, {1.0, 2.0, 3.0}, 10.0} == SpellTarget.target_query(spell, Target.at({1.0, 2.0, 3.0}))
    end
  end
end
