defmodule ThistleTea.Game.MathTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Math

  describe "random_int/2" do
    test "returns integer in range with integer inputs" do
      result = Math.random_int(1, 10)
      assert is_integer(result)
      assert result >= 1
      assert result <= 10
    end

    test "rounds float inputs to integers" do
      result = Math.random_int(1.5, 10.5)
      assert is_integer(result)
      assert result >= 1
      assert result <= 11
    end

    test "handles same min and max" do
      assert Math.random_int(5, 5) == 5
    end
  end

  describe "within_range/2" do
    test "returns true within default range" do
      assert Math.within_range({0, 0, 0}, {1, 1, 1})
      assert Math.within_range({0, 0, 0}, {250, 250, 250})
    end

    test "returns false outside default range" do
      refute Math.within_range({0, 0, 0}, {251, 0, 0})
      refute Math.within_range({0, 0, 0}, {0, 251, 0})
      refute Math.within_range({0, 0, 0}, {0, 0, 251})
    end

    test "handles negative coordinates" do
      assert Math.within_range({-100, -100, -100}, {-90, -90, -90})
    end
  end

  describe "within_range/3" do
    test "respects custom range" do
      assert Math.within_range({0, 0, 0}, {10, 10, 10}, 10)
      refute Math.within_range({0, 0, 0}, {11, 0, 0}, 10)
    end
  end

  describe "movement_duration/3" do
    test "calculates correct duration for 3-4-5 triangle" do
      assert Math.movement_duration({0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, 1.0) == 5.0
    end

    test "returns zero for same position" do
      assert Math.movement_duration({0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, 1.0) == 0.0
    end

    test "scales with speed" do
      assert Math.movement_duration({0.0, 0.0, 0.0}, {6.0, 8.0, 0.0}, 2.0) == 5.0
    end

    test "raises with zero speed" do
      assert_raise FunctionClauseError, fn ->
        Math.movement_duration({0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, 0.0)
      end
    end
  end

  describe "movement_duration/2" do
    test "sums durations across path" do
      path = [{0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, {3.0, 4.0, 5.0}]
      assert Math.movement_duration(path, 1.0) == 10.0
    end

    test "returns zero for single point" do
      path = [{0.0, 0.0, 0.0}]
      assert Math.movement_duration(path, 1.0) == 0.0
    end
  end
end
