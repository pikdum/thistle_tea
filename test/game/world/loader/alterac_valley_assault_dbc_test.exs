defmodule ThistleTea.Game.World.Loader.AlteracValleyAssaultDBCTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.DBC

  @moduletag :dbc_db

  describe "altar completion spells" do
    test "each altar sends its corresponding ceremony event" do
      for {spell_id, event_id} <- [{21_249, 7_060}, {21_648, 7_268}] do
        spell = DBC.get(DBC.Spell, spell_id)
        assert {spell.effect_0, spell.effect_misc_value_0} == {61, event_id}
      end
    end
  end

  describe "beacon spells" do
    test "enemy disarming uses the client's five second attacking cast and lock type fourteen" do
      spell = DBC.get!(DBC.Spell, 8_386)
      assert {spell.effect_0, spell.effect_misc_value_0} == {33, 14}
      assert DBC.get!(DBC.SpellCastTimes, spell.casting_time_index).base == 5_000
      lock = DBC.get!(DBC.Lock, 99)
      assert Enum.any?(0..7, &(Map.fetch!(lock, :"ty_#{&1}") == 2 and Map.fetch!(lock, :"property_#{&1}") == 14))
    end
  end
end
