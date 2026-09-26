defmodule ThistleTea.Game.World.Loader.SlowExclusivityDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "classifies class snares and melee-speed penalties from real effect data" do
      for id <- [116, 120, 1715, 2974, 3409, 3600, 5116, 8056, 11_201, 12_323] do
        assert SpellLoader.load(id).exclusive_category == :snare
      end

      assert SpellLoader.load(6343).exclusive_category == :negative_haste
    end

    test "exempts daze and spells that carry other aura effects" do
      assert SpellLoader.load(1604).exclusive_category == nil
      assert SpellLoader.load(1098).exclusive_category == nil
      assert SpellLoader.load(22_812).exclusive_category == nil
    end
  end
end
