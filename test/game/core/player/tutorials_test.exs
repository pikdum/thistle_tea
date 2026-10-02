defmodule ThistleTea.Game.Core.Player.TutorialsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Player.Tutorials

  describe "mark/2" do
    test "sets the seen bit in its word and ignores out-of-range indexes" do
      flags = Tutorials.new() |> Tutorials.mark(0) |> Tutorials.mark(33) |> Tutorials.mark(255) |> Tutorials.mark(256)
      assert flags == [1, 2, 0, 0, 0, 0, 0, 0x80000000]
      assert Tutorials.all_seen() == List.duplicate(0xFFFFFFFF, 8)
    end
  end
end
