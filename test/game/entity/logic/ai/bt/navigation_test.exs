defmodule ThistleTea.Game.Entity.Logic.AI.BT.NavigationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.WorldRef

  describe "target_valid_same_map?/3" do
    test "uses supplied perception" do
      world = %WorldRef{map_id: 1}

      context =
        context(
          observations: %{
            42 => %Observation{guid: 42, position: {world, 1.0, 2.0, 3.0}}
          }
        )

      entity = entity(world: world)

      assert Navigation.target_valid_same_map?(entity, 42, context)
      refute Navigation.target_valid_same_map?(entity, 7, context)
    end
  end

  describe "chase/4" do
    test "emits a typed intent that the owner resolves" do
      world = %WorldRef{map_id: 1}

      requested = Navigation.chase(entity(world: world), 42, {5.0, 0.0, 0.0}, context())

      assert [
               %NavigationIntent{
                 destination: destination,
                 opts: [face_target: 42]
               }
             ] = requested.internal.navigation_intents

      assert destination == {5.0, 0.0, 0.0}

      find_path = fn _map_id, _start, _destination ->
        [{2.0, 0.0, 0.0}, {5.0, 0.0, 0.0}]
      end

      moved = NavigationResolver.resolve(requested, 0, find_path)
      assert moved.movement_block.spline_nodes == [{2.0, 0.0, 0.0}, {5.0, 0.0, 0.0}]
      assert moved.internal.navigation_intents == []
    end

    test "drains a request when no path is available" do
      requested = Navigation.chase(entity(world: %WorldRef{map_id: 1}), 42, {5.0, 0.0, 0.0}, context())
      unchanged = NavigationResolver.resolve(requested, 0, fn _map_id, _start, _destination -> nil end)

      assert unchanged.movement_block.spline_nodes == []
      assert unchanged.internal.navigation_intents == []
    end
  end

  describe "wait_for_arrival/4" do
    test "yields to the owner while a navigation request is pending" do
      requested = Navigation.move_to(entity(world: %WorldRef{map_id: 1}), {5.0, 0.0, 0.0}, [], context())

      assert {{:running, 0, :navigation}, ^requested, %Blackboard{}} =
               Navigation.wait_for_arrival(requested, Blackboard.new(), context())
    end

    test "chooses the earliest supplied wake" do
      moving =
        entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 1_000,
          spline_nodes: [{10.0, 0.0, 0.0}]
        )

      assert {{:running, 100, :aggro}, ^moving, %Blackboard{}} =
               Navigation.wait_for_arrival(moving, Blackboard.new(), context(), [{:aggro, 100}])
    end
  end

  defp context(opts \\ []) do
    perception = Perception.new(0, nil, Keyword.get(opts, :observations, %{}), %{mobs: [], players: []})

    Context.new(0, perception: perception)
  end

  defp entity(opts) do
    world = Keyword.get(opts, :world, %WorldRef{map_id: 0})

    %{
      internal: %Internal{
        world: world,
        running: false,
        movement_start_time: Keyword.get(opts, :start_time),
        movement_start_position: Keyword.get(opts, :start_position)
      },
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        walk_speed: 2.5,
        run_speed: 7.0,
        duration: Keyword.get(opts, :duration, 0),
        spline_nodes: Keyword.get(opts, :spline_nodes, [])
      }
    }
  end
end
