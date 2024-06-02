defmodule ThistleTeaTest do
  use ExUnit.Case
  doctest ThistleTea

  test "greets the world" do
    assert ThistleTea.hello() == :world
  end
end
