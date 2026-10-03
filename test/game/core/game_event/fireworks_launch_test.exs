defmodule ThistleTea.Game.Core.GameEvent.FireworksLaunchTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.FireworksLaunch

  describe "sites/2" do
    test "launches over the city nearest the speaker on its map" do
      stormwind = FireworksLaunch.sites(0, {-8862.0, 654.0, 96.0, 0.0})
      booty_bay = FireworksLaunch.sites(0, {-14_307.0, 508.0, 9.0, 0.0})
      orgrimmar = FireworksLaunch.sites(1, {1503.0, -4409.0, 22.0, 0.0})

      assert length(stormwind) == 117
      assert {-14_358.03, 515.058, 34.2664, 3.68265} in booty_bay
      refute Enum.any?(stormwind, &(&1 in booty_bay))
      assert Enum.all?(orgrimmar, fn {x, _y, _z, _o} -> x > 1000.0 end)
    end

    test "has no sites away from the cities" do
      assert FireworksLaunch.sites(0, {-9464.0, 62.0, 56.0, 0.0}) == []
      assert FireworksLaunch.sites(1, {-8862.0, 654.0, 96.0, 0.0}) == []
    end
  end

  describe "speaker?/1" do
    test "is the cheer speaker" do
      assert FireworksLaunch.speaker?(180_749)
      refute FireworksLaunch.speaker?(180_754)
    end
  end
end
