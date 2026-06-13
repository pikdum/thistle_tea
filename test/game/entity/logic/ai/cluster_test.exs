defmodule ThistleTea.Game.Entity.Logic.AI.ClusterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.AI.Cluster

  describe "free_angle/2" do
    test "keeps the desired angle when nothing is occupied" do
      assert Cluster.free_angle(0.7, []) == 0.7
    end

    test "keeps the desired angle when occupied sectors are elsewhere" do
      assert Cluster.free_angle(0.0, [{:math.pi(), 0.3}]) == 0.0
    end

    test "slides to the edge of a blocking sector centered on the desired angle" do
      angle = Cluster.free_angle(0.0, [{0.0, 0.5}])

      assert_in_delta abs(angle), 0.5, 0.01
    end

    test "picks the open side when one edge is congested" do
      angle = Cluster.free_angle(0.0, [{0.0, 0.5}, {-0.6, 0.3}])

      assert_in_delta angle, 0.5, 0.01
    end

    test "clears occupants across the -pi/pi wrap-around boundary" do
      pi = :math.pi()
      occupied = [{-pi + 0.05, 0.4}]

      angle = Cluster.free_angle(pi, occupied)

      assert angular_distance(angle, -pi + 0.05) >= 0.4 - 0.001
    end
  end

  defp angular_distance(a, b) do
    abs(:math.atan2(:math.sin(a - b), :math.cos(a - b)))
  end
end
