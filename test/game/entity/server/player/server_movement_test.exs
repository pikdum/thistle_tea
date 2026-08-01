defmodule ThistleTea.Game.Entity.Server.Player.ServerMovementTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Server.Player.ServerMovement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.WorldRef

  describe "start/3" do
    test "publishes a charge as projected movement until arrival" do
      state = state()
      guid = state.guid
      on_exit(fn -> World.remove_position(state.character) end)

      state = ServerMovement.start(state, command(), 1_000)

      assert %ServerMovement{} = state.server_movement

      assert Position.projection(guid) ==
               {WorldRef.open(0), {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 100}

      assert World.position(guid, 1_050) == {WorldRef.open(0), 5.0, 0.0, 0.0}

      token = state.server_movement.token
      state = ServerMovement.finish(state, token, 1_100)

      assert state.server_movement == nil
      assert state.character.movement_block.position == {10.0, 0.0, 0.0, 0.0}
      assert Position.projection(guid) == nil
      assert World.position(guid, 1_100) == {WorldRef.open(0), 10.0, 0.0, 0.0}
    end

    test "ignores an arrival from a superseded movement" do
      state = ServerMovement.start(state(), command(), 1_000)
      on_exit(fn -> World.remove_position(state.character) end)

      assert ServerMovement.finish(state, make_ref(), 1_100) == state
      Process.cancel_timer(state.server_movement.timer_ref)
    end
  end

  describe "cancel/2" do
    test "stops at the projected position and clears the projection" do
      state = ServerMovement.start(state(), command(), 1_000)
      guid = state.guid
      on_exit(fn -> World.remove_position(state.character) end)

      state = ServerMovement.cancel(state, 1_050)

      assert state.server_movement == nil
      assert state.character.movement_block.position == {5.0, 0.0, 0.0, 0.0}
      assert Position.projection(guid) == nil
      assert World.position(guid, 1_050) == {WorldRef.open(0), 5.0, 0.0, 0.0}
    end
  end

  defp state do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

    character = %Character{
      object: %Object{guid: guid},
      internal: %Internal{world: WorldRef.open(0), spline_id: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}
    }

    %State{guid: guid, character: character}
  end

  defp command do
    %Commands.ChargePathResolved{
      path: [{10.0, 0.0, 0.0}],
      duration_ms: 100,
      started_at: 1_000
    }
  end
end
