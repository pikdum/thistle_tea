defmodule ThistleTea.Game.Entity.Logic.AI.BT.NavigationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation, as: PathSource
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.WorldRef

  describe "target_valid_same_map?/3" do
    test "uses supplied perception" do
      world = %WorldRef{map_id: 1}

      context =
        context(
          position: fn
            42 -> {world, 1.0, 2.0, 3.0}
            _guid -> nil
          end
        )

      entity = entity(world: world)

      assert Navigation.target_valid_same_map?(entity, 42, context)
      refute Navigation.target_valid_same_map?(entity, 7, context)
    end
  end

  describe "chase/4" do
    test "starts movement along the boundary-supplied path" do
      world = %WorldRef{map_id: 1}

      navigation = %PathSource{
        find_path: fn _map_id, _start, _destination ->
          [{2.0, 0.0, 0.0}, {5.0, 0.0, 0.0}]
        end,
        find_random_point: fn _map, _anchor, _radius -> nil end
      }

      context = context(navigation: navigation)

      assert {:ok, moved} = Navigation.chase(entity(world: world), 42, {5.0, 0.0, 0.0}, context)
      assert moved.movement_block.spline_nodes == [{2.0, 0.0, 0.0}, {5.0, 0.0, 0.0}]
    end
  end

  describe "wait_for_arrival/4" do
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
    perception = %{
      Perception.empty()
      | position: Keyword.get(opts, :position, fn _guid -> nil end)
    }

    Context.new(0,
      perception: perception,
      navigation: Keyword.get(opts, :navigation, PathSource.direct())
    )
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
