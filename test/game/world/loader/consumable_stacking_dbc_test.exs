defmodule ThistleTea.Game.World.Loader.ConsumableStackingDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellElixir

  @moduletag :dbc_db

  describe "load/1" do
    test "classifies native foods, drinks, combined recovery, and Well Fed" do
      for {id, category} <- [
            {5004, :food},
            {434, :food},
            {430, :drink},
            {1137, :drink},
            {24_707, :food_and_drink},
            {25_990, :food_and_drink},
            {19_705, :well_fed},
            {19_711, :well_fed},
            {24_799, :well_fed},
            {18_125, :well_fed},
            {18_141, :well_fed},
            {23_697, :well_fed}
          ] do
        assert SpellLoader.load(id).exclusive_category == category
      end

      assert SpellLoader.load(18_192).exclusive_category == nil
    end

    test "combines cached elixir masks with DBC data" do
      id = 17_626
      previous = :ets.lookup(SpellElixir, id)

      on_exit(fn ->
        :ets.delete(SpellElixir, id)
        :ets.insert(SpellElixir, previous)
      end)

      :ets.insert(SpellElixir, {id, 3})
      assert SpellLoader.load(id).exclusive_category == :flask
    end
  end
end
