defmodule ThistleTea.Game.World.Loader.FadeDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "build_spellbook/1" do
    test "loads Fade's duration, level scaling, and temporary threat reduction" do
      spell = SpellLoader.build_spellbook([10_941])[10_941]
      assert spell.duration_ms == 10_000
      assert Spell.attribute?(spell, :no_threat)
      assert [%Effect{aura: :mod_total_threat, implicit_target_a: :caster} = effect] = spell.effects
      assert Effect.roll(effect, Spell.level_units(spell, 50)) == -620
      assert Effect.roll(effect, Spell.level_units(spell, 60)) == -650
    end
  end
end
