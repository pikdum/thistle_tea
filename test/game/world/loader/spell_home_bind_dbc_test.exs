defmodule ThistleTea.Game.World.Loader.SpellHomeBindDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads the innkeeper bind effect" do
      spell = SpellLoader.load(3286)
      assert spell.name == "Bind"

      assert [
               %{type: :bind, semantic: %Semantics.Movement{kind: :bind}},
               %{type: :create_item, item_type: 6948}
             ] = spell.effects
    end

    test "Hearthstone and Astral Recall use the same home destination" do
      for id <- [556, 8690] do
        spell = SpellLoader.load(id)
        assert spell.cast_time_ms == 10_000
        assert [%{type: :teleport_units, implicit_target_a: :caster, implicit_target_b: :home_bind} | _] = spell.effects
      end
    end
  end
end
