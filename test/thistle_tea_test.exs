defmodule ThistleTeaTest do
  use ExUnit.Case
  import ThistleTea.Mob

  test "future_position" do
    assert future_position(0, 0, 0, 1, 1) == {1, 0}
    assert future_position(0, 0, 0, 10, 1) == {10, 0}
    assert future_position(0, 0, 0, 1, 10) == {10, 0}
    {x, _} = future_position(0, 0, :math.pi(), 1, 10)
    assert x == -10
  end
end
