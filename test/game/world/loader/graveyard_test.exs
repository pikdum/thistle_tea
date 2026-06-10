defmodule ThistleTea.Game.World.Loader.GraveyardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.Graveyard

  @alliance 469
  @horde 67

  defp graveyard(id, map, position, faction \\ 0) do
    %{id: id, map: map, position: position, faction: faction}
  end

  describe "team_for_race/1" do
    test "alliance races" do
      for race <- [1, 3, 4, 7], do: assert(Graveyard.team_for_race(race) == @alliance)
    end

    test "horde races" do
      for race <- [2, 5, 6, 8], do: assert(Graveyard.team_for_race(race) == @horde)
    end
  end

  describe "closest_of/4" do
    test "picks nearest graveyard on the same map" do
      graveyards = [
        graveyard(1, 0, {100.0, 0.0, 0.0}),
        graveyard(2, 0, {10.0, 0.0, 0.0}),
        graveyard(3, 0, {50.0, 0.0, 0.0})
      ]

      assert %{id: 2} = Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @alliance)
    end

    test "skips enemy faction graveyards" do
      graveyards = [
        graveyard(1, 0, {10.0, 0.0, 0.0}, @horde),
        graveyard(2, 0, {100.0, 0.0, 0.0}, @alliance)
      ]

      assert %{id: 2} = Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @alliance)
    end

    test "neutral graveyards are allowed for both teams" do
      graveyards = [graveyard(1, 0, {10.0, 0.0, 0.0}, 0)]

      assert %{id: 1} = Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @horde)
      assert %{id: 1} = Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @alliance)
    end

    test "falls back to another map when none on the same map" do
      graveyards = [graveyard(1, 1, {10.0, 0.0, 0.0})]

      assert %{id: 1} = Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @alliance)
    end

    test "nil when nothing is allowed" do
      graveyards = [graveyard(1, 0, {10.0, 0.0, 0.0}, @horde)]

      assert Graveyard.closest_of(graveyards, 0, {0.0, 0.0, 0.0}, @alliance) == nil
    end
  end
end
