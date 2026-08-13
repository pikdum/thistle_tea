defmodule ThistleTea.Game.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Battleground

  describe "team_for_race/1" do
    test "maps Vanilla player races to their battleground teams" do
      assert Enum.all?([1, 3, 4, 7], &(Battleground.team_for_race(&1) == :alliance))
      assert Enum.all?([2, 5, 6, 8], &(Battleground.team_for_race(&1) == :horde))
      assert Battleground.team_for_race(9) == nil
    end
  end

  describe "bracket/1" do
    test "maps eligible levels to the six Vanilla brackets" do
      assert Enum.map([10, 20, 30, 40, 50, 60], &Battleground.bracket/1) == Enum.to_list(0..5)
      assert Battleground.bracket(9) == nil
      assert Battleground.bracket(61) == nil
    end
  end
end
