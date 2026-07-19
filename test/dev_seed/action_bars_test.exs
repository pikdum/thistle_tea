defmodule ThistleTea.DevSeed.ActionBarsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DevSeed.ActionBars

  describe "visible_toggles/0" do
    test "shows every auxiliary action bar" do
      assert ActionBars.visible_toggles() == 0x0F
    end
  end

  describe "build/2" do
    test "uses the highest learned rank in the configured slot" do
      spells = [
        spell(133, "Fireball", 1),
        spell(143, "Fireball", 6),
        spell(10_149, "Fireball", 48),
        spell(10_180, "Frostbolt", 48),
        spell(3561, "Teleport: Stormwind", 20)
      ]

      buttons = ActionBars.build(8, spells)

      assert buttons[1] == 10_149
      assert buttons[2] == 10_180
      assert buttons[27] == 3561
      refute 133 in Map.values(buttons)
      refute 143 in Map.values(buttons)
    end

    test "places warrior abilities on their stance pages" do
      buttons =
        ActionBars.build(1, [
          spell(11_578, "Charge", 46),
          spell(11_600, "Revenge", 44),
          spell(23_923, "Shield Slam", 48),
          spell(20_616, "Intercept", 42)
        ])

      assert buttons[75] == 11_578
      assert buttons[86] == 11_600
      assert buttons[94] == 23_923
      assert buttons[101] == 20_616
    end

    test "places druid abilities on their form pages" do
      buttons =
        ActionBars.build(11, [
          spell(8905, "Wrath", 46),
          spell(9849, "Claw", 40),
          spell(9880, "Maul", 50)
        ])

      assert buttons[0] == 8905
      assert buttons[73] == 9849
      assert buttons[97] == 9880
    end

    test "skips configured spells the character has not learned" do
      assert ActionBars.build(8, []) == %{}
      assert ActionBars.build(6, [spell(1, "Anything", 1)]) == %{}
    end
  end

  defp spell(id, name, level) do
    %{id: id, name: name, level: level, base_level: level}
  end
end
