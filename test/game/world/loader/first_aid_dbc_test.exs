defmodule ThistleTea.Game.World.Loader.FirstAidDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "bandages retain their shared mechanic, healing cadence, and damage interruption" do
      for id <- [746, 1159, 3267, 3268, 7926, 7927, 10_838, 10_839, 18_608, 18_610, 23_567, 24_414, 30_020] do
        spell = SpellLoader.load(id)
        assert spell.mechanic == 16
        assert Spell.attribute?(spell, :channeled)
        assert spell.aura_interrupt_flags == 2
        assert [%Effect{type: :apply_aura, aura: :periodic_heal, amplitude_ms: 1000}] = spell.effects
      end

      assert SpellLoader.load(18_610).duration_ms == 8000
      assert hd(SpellLoader.load(18_610).effects).base_points == 249
    end

    test "Recently Bandaged supplies a one-minute negative mechanic immunity" do
      spell = SpellLoader.load(11_196)
      assert spell.duration_ms == 60_000
      assert Spell.attribute?(spell, :negative)
      assert [%Effect{type: :apply_aura, aura: :mechanic_immunity, misc_value: 16}] = spell.effects
    end
  end
end
