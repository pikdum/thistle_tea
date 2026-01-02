defmodule ThistleTea.Game.Entity.Logic.AI.HTN.Mob do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.HTN
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World.Pathfinding

  def htn do
    HTN.new()
    |> HTN.root(:mob_behavior)
    |> HTN.task(:mob_behavior, [
      HTN.method(&dead?/1, [:idle_dead]),
      HTN.method(&has_waypoints?/1, [:pick_waypoint, :move_to_target, :apply_waypoint, :wait_waypoint]),
      HTN.method(&can_wander?/1, [:pick_wander_point, :move_to_target, :wait_after_move]),
      HTN.method(fn _ -> true end, [:idle])
    ])
    |> HTN.step(:pick_wander_point, &pick_wander_point/2)
    |> HTN.step(:pick_waypoint, &pick_waypoint/2)
    |> HTN.step(:move_to_target, &move_to_target/2)
    |> HTN.step(:apply_waypoint, &apply_waypoint/2)
    |> HTN.step(:wait_after_move, &wait_after_move/2)
    |> HTN.step(:wait_waypoint, &wait_waypoint/2)
    |> HTN.step(:idle, &idle/2)
    |> HTN.step(:idle_dead, &idle_dead/2)
  end

  defp dead?(%Mob{unit: %Unit{health: health}}) when is_number(health) do
    health <= 0
  end

  defp dead?(%Mob{}) do
    false
  end

  defp has_waypoints?(%Mob{internal: %Internal{waypoint_route: %WaypointRoute{}}}) do
    true
  end

  defp has_waypoints?(%Mob{}) do
    false
  end

  defp can_wander?(%Mob{internal: %Internal{movement_type: 1}}) do
    true
  end

  defp can_wander?(%Mob{}) do
    false
  end

  defp pick_wander_point(%Mob{} = state, ctx) do
    case Pathfinding.find_random_point_around_circle(
           state.internal.map,
           state.internal.initial_position,
           state.internal.spawn_distance
         ) do
      nil ->
        {:replan, state, Map.drop(ctx, [:target, :orientation, :wait_time]), idle_delay()}

      {x, y, z} ->
        {:ok, state, Map.put(ctx, :target, {x, y, z}), 0}
    end
  end

  defp pick_waypoint(%Mob{} = state, ctx) do
    case waypoint_destination(state) do
      nil ->
        {:replan, state, Map.drop(ctx, [:target, :orientation, :wait_time]), idle_delay()}

      %{position: {x, y, z, o}, wait_time: wait_time} ->
        ctx =
          ctx
          |> Map.put(:target, {x, y, z})
          |> Map.put(:orientation, o)
          |> Map.put(:wait_time, wait_time || 0)

        {:ok, state, ctx, 0}
    end
  end

  defp move_to_target(%Mob{} = state, ctx) do
    case Map.get(ctx, :target) do
      {x, y, z} ->
        state = Movement.move_to(state, {x, y, z})
        {:ok, state, ctx, move_duration(state)}

      _ ->
        {:replan, state, Map.drop(ctx, [:target]), idle_delay()}
    end
  end

  defp apply_waypoint(%Mob{} = state, ctx) do
    state =
      case Map.get(ctx, :orientation) do
        o when is_number(o) -> set_orientation(state, o)
        _ -> state
      end

    state = increment_waypoint(state)
    {:ok, state, ctx, 0}
  end

  defp wait_after_move(%Mob{} = state, ctx) do
    {:ok, state, ctx, wander_wait_delay()}
  end

  defp wait_waypoint(%Mob{} = state, ctx) do
    delay = Map.get(ctx, :wait_time, 0)
    {:ok, state, Map.drop(ctx, [:target, :orientation, :wait_time]), delay}
  end

  defp idle(%Mob{} = state, ctx) do
    {:ok, state, ctx, idle_delay()}
  end

  defp idle_dead(%Mob{} = state, ctx) do
    {:ok, state, ctx, idle_dead_delay()}
  end

  defp waypoint_destination(%Mob{internal: %Internal{waypoint_route: %WaypointRoute{} = route}}) do
    WaypointRoute.destination_waypoint(route)
  end

  defp waypoint_destination(%Mob{}) do
    nil
  end

  defp increment_waypoint(%Mob{internal: %Internal{waypoint_route: %WaypointRoute{} = route} = internal} = state) do
    route = WaypointRoute.increment_waypoint(route)
    %{state | internal: %{internal | waypoint_route: route}}
  end

  defp increment_waypoint(%Mob{} = state) do
    state
  end

  defp set_orientation(%Mob{movement_block: %MovementBlock{position: {x, y, z, _o}}} = state, o) do
    %{state | movement_block: %{state.movement_block | position: {x, y, z, o}}}
  end

  defp move_duration(%Mob{movement_block: %MovementBlock{duration: duration}}) do
    duration || 0
  end

  defp idle_delay do
    :rand.uniform(4_000) + 2_000
  end

  defp idle_dead_delay do
    :rand.uniform(10_000) + 10_000
  end

  defp wander_wait_delay do
    :rand.uniform(6_000) + 4_000
  end
end
