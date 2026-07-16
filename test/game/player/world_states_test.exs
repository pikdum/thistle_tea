defmodule ThistleTea.Game.Player.WorldStatesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network.Message.SmsgInitWorldStates
  alias ThistleTea.Game.Player.WorldStates
  alias ThistleTea.Game.WorldRef

  describe "build/2" do
    test "uses the destination map and zone" do
      character = %Character{
        internal: %Internal{world: WorldRef.instance(389, 12), area: 0},
        movement_block: %MovementBlock{position: {-8.23, -43.26, -21.81, 0.0}}
      }

      resolver = fn 389, {-8.23, -43.26, -21.81} -> {2437, 2437} end

      assert WorldStates.build(character, resolver) ==
               %SmsgInitWorldStates{map: 389, area: 2437, states: []}
    end
  end
end
