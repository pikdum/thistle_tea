defmodule ThistleTea.Game.Core.Player.CinematicTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Player.Cinematic

  @human [
    {0, {-8960.0, 517.0, 86.0}},
    {1_000, {-8960.0, 517.0, 86.0}},
    {30_000, {-9038.0, 458.0, 83.0}},
    {70_000, {-8949.0, -132.0, 83.0}}
  ]
  @northshire {-8949.95, -132.49, 83.53, 0.0}

  setup do
    %{cinematic: 81 |> Cinematic.prepare(@human, @northshire) |> Cinematic.begin(10_000)}
  end

  describe "camera/2" do
    test "starts on the initial waypoint and follows the latest one passed", %{cinematic: cinematic} do
      assert Cinematic.camera(cinematic, 10_000) == {:view, {-8960.0, 517.0, 86.0}}
      assert Cinematic.camera(cinematic, 40_000) == {:view, {-8960.0, 517.0, 86.0}}
      assert Cinematic.camera(cinematic, 40_001) == {:view, {-9038.0, 458.0, 83.0}}
    end

    test "returns the view to the player once the camera is back in line with them", %{cinematic: cinematic} do
      assert Cinematic.camera(cinematic, 80_001) == :reset
    end

    test "finishes a few seconds after the last waypoint", %{cinematic: cinematic} do
      assert Cinematic.camera(cinematic, 85_000) == :reset
      assert Cinematic.camera(cinematic, 85_001) == :finished
    end

    test "keeps the player's view before a path without a starting waypoint begins" do
      cinematic = 2 |> Cinematic.prepare([{1_000, {100.0, 100.0, 0.0}}], @northshire) |> Cinematic.begin(0)
      assert Cinematic.camera(cinematic, 500) == :reset
      assert Cinematic.camera(cinematic, 1_001) == {:view, {100.0, 100.0, 0.0}}
    end
  end

  describe "next_check_in/2" do
    test "wakes just after the next waypoint, then at the end", %{cinematic: cinematic} do
      assert Cinematic.next_check_in(cinematic, 10_000) == 1_001
      assert Cinematic.next_check_in(cinematic, 11_001) == 29_000
      assert Cinematic.next_check_in(cinematic, 80_001) == 5_000
      assert Cinematic.next_check_in(cinematic, 85_001) == nil
    end
  end

  describe "begin/2" do
    test "keeps the clock of a cinematic already under way", %{cinematic: cinematic} do
      assert Cinematic.begin(cinematic, 99_000) == cinematic
    end
  end
end
