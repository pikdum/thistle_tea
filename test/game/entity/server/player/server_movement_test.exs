defmodule ThistleTea.Game.Entity.Server.Player.ServerMovementTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Confusion
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Player.ServerMovement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.WorldRef

  describe "start/3" do
    test "publishes a charge as projected movement until arrival" do
      state = state()
      guid = state.guid
      on_exit(fn -> World.remove_position(state.character) end)

      state = ServerMovement.start(state, command(), 1_000)

      assert %ServerMovement{} = state.server_movement

      assert Position.projection(guid) == %Spline{
               world: WorldRef.open(0),
               origin: {0.0, 0.0, 0.0},
               nodes: [{10.0, 0.0, 0.0}],
               started_at: 1_000,
               duration_ms: 100
             }

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
    test "cancels confusion movement and reanchors after relocation" do
      state = controlled_state()
      character = Movement.move_along_path(state.character, [{2.5, 0.0, 0.0}], [run?: false], 1_000)
      state = %{state | character: character}
      on_exit(fn -> World.remove_position(state.character) end)

      state = ServerMovement.cancel(state, 1_500)
      assert state.character.movement_block.position == {1.25, 0.0, 0.0, 0.0}
      assert state.character.internal.blackboard.confusion == nil
      assert state.character.internal.running
      assert ControlMovement.active?(state.character)
      assert state.character.unit.auras |> hd() |> Map.fetch!(:expires_at) == 10_000

      character = %{
        state.character
        | movement_block: %{state.character.movement_block | position: {100.0, 0.0, 0.0, 0.0}}
      }

      assert ThistleTea.Game.Entity.Logic.AI.BT.Confusion.request(character, 1_500) == {0, {100.0, 0.0, 0.0}, 4.0}
    end

    test "restores running when cancelled during a confusion pause" do
      state = controlled_state()
      state = ServerMovement.cancel(state, 1_500)
      assert state.character.internal.blackboard.confusion == nil
      assert state.character.internal.running
      assert ControlMovement.active?(state.character)
    end

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

  describe "advance/2" do
    test "publishes player spline progress and clears the projection after arrival" do
      state = state()
      character = Movement.move_along_path(state.character, [{7.0, 0.0, 0.0}], [], 1_000)
      state = %{state | character: character}
      on_exit(fn -> World.remove_position(state.character) end)
      state = ServerMovement.advance(state, 1_500)
      assert state.character.movement_block.position == {3.5, 0.0, 0.0, 0.0}
      assert World.position(state.guid, 1_500) == {WorldRef.open(0), 3.5, 0.0, 0.0}
      state = ServerMovement.advance(state, 2_001)
      assert state.character.movement_block.position == {7.0, 0.0, 0.0, 0.0}
      assert Position.projection(state.guid) == nil
    end
  end

  describe "reconcile/1" do
    test "an interrupted charge cannot finish a later forced movement" do
      state = ServerMovement.start(state(), command(), 1_000)
      token = state.server_movement.token
      character = controlled_state(state).character
      state = ServerMovement.reconcile(%{state | character: character})
      on_exit(fn -> World.remove_position(state.character) end)
      assert state.server_movement == nil
      assert ServerMovement.finish(state, token, 1_100) == state
    end
  end

  defp controlled_state(state \\ state()) do
    holder = %Holder{
      spell: %Spell{id: 1},
      expires_at: 10_000,
      auras: [%Aura{type: :mod_confuse}]
    }

    character = %{state.character | unit: %Unit{health: 100, auras: [holder]}}

    blackboard = %Blackboard{
      confusion: %Confusion{anchor: {0.0, 0.0, 0.0}, previous_running: true}
    }

    %{state | character: %{character | internal: %{character.internal | running: false, blackboard: blackboard}}}
  end

  defp state do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

    character = %Character{
      object: %Object{guid: guid},
      internal: %Internal{world: WorldRef.open(0), spline_id: 0, running: true},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0, run_speed: 7.0, walk_speed: 2.5}
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
