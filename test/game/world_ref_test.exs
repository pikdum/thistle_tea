defmodule ThistleTea.Game.WorldRefTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.WorldRef

  describe "open/1" do
    test "identifies the shared open-world copy of a map" do
      assert WorldRef.open(1) == %WorldRef{map_id: 1, instance_id: nil}
      assert WorldRef.open?(WorldRef.open(1))
    end
  end

  describe "instance/2" do
    test "isolates copies that share physical map geometry" do
      first = WorldRef.instance(389, 1)
      second = WorldRef.instance(389, 2)

      assert first.map_id == second.map_id
      refute first == second
      refute WorldRef.open?(first)
    end
  end
end
