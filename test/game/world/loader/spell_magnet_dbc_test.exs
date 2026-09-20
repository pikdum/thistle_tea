defmodule ThistleTea.Game.World.Loader.SpellMagnetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellMagnet
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Grounding Totem supplies a shared single-charge party aura" do
      spell = SpellLoader.load(8178)
      assert spell.proc_charges == 1
      assert [%{type: :apply_area_aura, aura: :spell_magnet, radius_yards: 20.0}] = spell.effects
    end

    test "recognizes harmful spells and the redirection bypass on Cause Insanity" do
      for id <- [133, 116, 172], do: assert(SpellMagnet.eligible?(SpellLoader.load(id)))
      for id <- [8004, 24_327, 26_180], do: refute(SpellMagnet.eligible?(SpellLoader.load(id)))
    end
  end
end
