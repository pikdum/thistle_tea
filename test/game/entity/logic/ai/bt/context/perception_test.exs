defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.PerceptionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.WorldRef

  describe "projected_position/3" do
    test "projects from the captured grounded position" do
      world = %WorldRef{map_id: 1}

      observation = %Observation{
        guid: 42,
        position: {world, 1.0, 2.0, 10.0},
        grounded_position: {world, 1.0, 2.0, 3.0},
        metadata: %{movement_velocity: {2.0, 0.0, 0.0}, moving_until: 2_000}
      }

      perception = Perception.new(1_000, nil, %{42 => observation}, %{mobs: [], players: []})

      assert Perception.projected_position(perception, 42, 500) == {world, 2.0, 2.0, 3.0}
    end
  end
end
