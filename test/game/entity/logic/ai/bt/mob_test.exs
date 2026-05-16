defmodule ThistleTea.Game.Entity.Logic.AI.BT.MobTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT

  describe "wait_until_wander_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_250}

      assert {{:running, 250}, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end

    test "succeeds when ready at explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_wander_at: 1_000}

      assert {:success, ^state, ^blackboard} =
               MobBT.wait_until_wander_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_until_waypoint_ready/3" do
    test "returns a running delay from explicit time" do
      state = fixture_mob()
      blackboard = %Blackboard{next_waypoint_at: 1_250}

      assert {{:running, 250}, ^state, ^blackboard} =
               MobBT.wait_until_waypoint_ready(state, blackboard, 1_000)
    end
  end

  describe "wait_for_arrival/3" do
    test "returns remaining movement duration from explicit time" do
      state = fixture_mob(start_time: 900, duration: 500)
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {{:running, 400}, ^state, ^blackboard} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end

    test "clears move target after arrival" do
      state = fixture_mob(start_time: 0, duration: 500)
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.wait_for_arrival(state, blackboard, 1_000)
    end
  end

  describe "move_to_target/3" do
    test "succeeds when already moving to target" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, move_target: {1.0, 2.0, 3.0}}

      assert {:success, ^state, ^blackboard} = MobBT.move_to_target(state, blackboard, 1_000)
    end

    test "fails and clears stale move target without a target" do
      state = fixture_mob()
      blackboard = %Blackboard{move_target: {1.0, 2.0, 3.0}}

      assert {:failure, ^state, %Blackboard{target: nil, move_target: nil}} =
               MobBT.move_to_target(state, blackboard, 1_000)
    end
  end

  describe "set_next_waypoint_wait/3" do
    test "schedules from explicit time and clears waypoint state" do
      state = fixture_mob()
      blackboard = %Blackboard{target: {1.0, 2.0, 3.0}, orientation: 1.5, wait_time: 250}

      assert {:success, ^state, %Blackboard{next_waypoint_at: 1_250, target: nil, orientation: nil, wait_time: nil}} =
               MobBT.set_next_waypoint_wait(state, blackboard, 1_000)
    end
  end

  defp fixture_mob(opts \\ []) do
    %Mob{
      internal: %Internal{
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: {0.0, 0.0, 0.0}
      },
      movement_block: %MovementBlock{
        duration: Keyword.get(opts, :duration, 0),
        position: {0.0, 0.0, 0.0, 0.0},
        spline_nodes: [{1.0, 0.0, 0.0}]
      }
    }
  end
end
