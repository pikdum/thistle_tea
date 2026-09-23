defmodule ThistleTea.Game.World.Loader.InsigniaSpellTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell

  @moduletag :dbc_db

  describe "load/1" do
    test "loads the native insignia spell as a one-second body interaction" do
      spell = Spell.load(22_027)
      assert spell.cast_time_ms == 1_000
      assert spell.range_yards == 10.0
      assert [%Effect{type: :remove_insignia}] = spell.effects
    end
  end
end
