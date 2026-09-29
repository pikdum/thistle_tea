defmodule ThistleTea.Game.World.Loader.SpellUnitTargetVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Spell.UnitTargets.Selector
  alias ThistleTea.Game.World.Loader.SpellUnitTarget

  @moduletag :vmangos_db

  setup do
    SpellUnitTarget.init()
    SpellUnitTarget.load_all()
    :ok
  end

  describe "get/1" do
    test "loads living and corpse alternatives for collection phials" do
      assert MapSet.new(SpellUnitTarget.get(11_513)) ==
               MapSet.new([
                 %Selector{entry: 6213},
                 %Selector{entry: 6329},
                 %Selector{entry: 6213, alive?: false},
                 %Selector{entry: 6329, alive?: false}
               ])

      assert Enum.all?(SpellUnitTarget.get(8593), &(not &1.alive?))
    end

    test "retains conditions and effect exclusions" do
      assert [%Selector{entry: 10_321, condition: %Condition{entry: 16_053}}] = SpellUnitTarget.get(16_053)
      assert [%Selector{entry: 15_218, inverse_effect_mask: 2}] = SpellUnitTarget.get(24_731)
      assert SpellUnitTarget.get(0) == []
    end
  end
end
