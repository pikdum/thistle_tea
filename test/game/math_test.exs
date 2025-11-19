defmodule ThistleTea.Game.MathTest do
  use ExUnit.Case

  alias ThistleTea.Game.Math

  test "movement duration" do
    assert Math.movement_duration({0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, 1.0) == 5.0
    path = [{0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, {3.0, 4.0, 5.0}]
    assert Math.movement_duration(path, 1.0) === 10.0
  end
end
