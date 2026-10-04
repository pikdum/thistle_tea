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
end
