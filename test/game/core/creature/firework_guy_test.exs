defmodule ThistleTea.Game.Core.Creature.FireworkGuyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Creature.FireworkGuy

  describe "launch/2" do
    test "a rocket bursts three yards over its launcher for the rocket credit" do
      assert FireworkGuy.launch(15_882, {1.0, 2.0, 3.0}) ==
               %{fireworks: [{180_851, {1.0, 2.0, 6.0, 0.0}}], credit: 15_893, lucky?: false}

      assert FireworkGuy.launch(15_888, {1.0, 2.0, 3.0}).fireworks == [{180_860, {1.0, 2.0, 6.0, 0.0}}]
    end

    test "a cluster fans its color's rockets around the launcher for the cluster credit" do
      assert %{fireworks: fireworks, credit: 15_894} = FireworkGuy.launch(15_873, {0.0, 0.0, 0.0})
      assert Enum.map(fireworks, &elem(&1, 0)) == List.duplicate(180_851, 5)

      assert Enum.map(fireworks, &elem(&1, 1)) == [
               {0.0, 0.0, 8.0, 0.0},
               {3.5, -1.0, 5.0, 0.0},
               {0.0, 2.0, 5.0, 0.0},
               {0.0, 0.0, 2.0, 0.0},
               {-3.5, -1.0, 5.0, 0.0}
             ]
    end

    test "a lucky cluster mixes its large rockets and brings Lunar Fortune" do
      assert %{fireworks: fireworks, credit: 15_894, lucky?: true} = FireworkGuy.launch(15_918, {0.0, 0.0, 0.0})
      assert Enum.map(fireworks, &elem(&1, 0)) == [180_861, 180_864, 180_864, 180_861, 180_861]
      assert List.last(fireworks) == {180_861, {0.0, 0.0, 12.0, 0.0}}
    end

    test "any other creature launches nothing" do
      assert FireworkGuy.launch(15_466, {0.0, 0.0, 0.0}) == nil
    end
  end
end
