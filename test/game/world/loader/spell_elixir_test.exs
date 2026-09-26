defmodule ThistleTea.Game.World.Loader.SpellElixirTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Consumable
  alias ThistleTea.Game.World.Loader.SpellElixir

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads all vanilla flask masks without restricting ordinary elixirs" do
      previous = :ets.tab2list(SpellElixir)

      on_exit(fn ->
        :ets.delete_all_objects(SpellElixir)
        :ets.insert(SpellElixir, previous)
      end)

      assert :ok = SpellElixir.load_all()

      for id <- [17_624, 17_626, 17_627, 17_628, 17_629] do
        assert SpellElixir.get(id) == 3
        assert Consumable.elixir_category(SpellElixir.get(id)) == :flask
      end

      for id <- [2374, 11_328, 17_538] do
        assert SpellElixir.get(id) == 0
        assert Consumable.elixir_category(SpellElixir.get(id)) == nil
      end

      assert SpellElixir.get(0) == 0
    end
  end
end
