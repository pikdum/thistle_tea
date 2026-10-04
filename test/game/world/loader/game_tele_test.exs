defmodule ThistleTea.Game.World.Loader.GameTeleTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.GameTele

  @locations [
    %{name: "DireMaulEast", map: 1, position: {-3980.8, 789.0, 161.0, 4.7}},
    %{name: "DireMaulNorth", map: 1, position: {-3521.3, 1085.2, 161.1, 4.7}},
    %{name: "brd", map: 230, position: {458.3, 26.5, -70.7, 4.9}},
    %{name: "brdpathbug", map: 230, position: {641.6, -199.2, -38.4, 1.4}},
    %{name: "DireforgeHill", map: 0, position: {-2838.6, -2875.5, 32.6, 0.3}}
  ]

  describe "search/2" do
    test "prefers an exact name over longer names that share it" do
      assert [%{name: "brd", map: 230}] = GameTele.search(@locations, " BRD ")
    end

    test "falls back to a prefix, then to a match anywhere in the name" do
      assert ["DireMaulEast", "DireMaulNorth"] = @locations |> GameTele.search("diremaul") |> Enum.map(& &1.name)
      assert [%{name: "DireforgeHill"}] = GameTele.search(@locations, "forge")
      assert GameTele.search(@locations, "stormwind") == []
    end
  end
end
