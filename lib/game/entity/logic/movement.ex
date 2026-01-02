defmodule ThistleTea.Game.Entity.Logic.Movement do
  use ThistleTea.Game.Network.Opcodes, [:SMSG_MONSTER_MOVE]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Pathfinding

  @max_u32 0xFFFFFFFF

  def increment_spline_id(%{internal: %Internal{spline_id: spline_id} = internal} = entity) do
    new_spline_id = increment_spline_id(spline_id)
    %{entity | internal: %{internal | spline_id: new_spline_id}}
  end

  def increment_spline_id(id) when is_integer(id) do
    rem(id, @max_u32) + 1
  end

  def is_moving?(%{internal: %Internal{movement_start_time: nil}}), do: false

  def is_moving?(%{
        movement_block: %MovementBlock{duration: duration},
        internal: %Internal{movement_start_time: start_time}
      })
      when is_integer(duration) and is_integer(start_time) and duration > 0 do
    current_time_ms() <= start_time + duration
  end

  def is_moving?(_), do: false

  def sync_position(%{movement_block: %MovementBlock{spline_nodes: spline_nodes}} = entity)
      when spline_nodes in [nil, []] do
    entity
  end

  def sync_position(%{movement_block: %MovementBlock{}, internal: %Internal{}} = entity) do
    if is_moving?(entity) do
      update_position_from_spline(entity)
    else
      finalize_movement(entity)
    end
  end

  def start_move_to(entity, {x, y, z}) do
    entity = sync_position(entity)

    %{
      movement_block: %MovementBlock{walk_speed: walk_speed, position: {x0, y0, z0, _o}} = mb,
      internal: %Internal{map: map, running: running} = internal
    } = entity

    path = Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

    if is_nil(path) do
      # handles maps that haven't been built yet
      raise "No path found from #{inspect({x0, y0, z0})} to #{inspect({x, y, z})}"
    end

    speed = if running, do: mb.run_speed * 7.0, else: walk_speed

    duration =
      [{x0, y0, z0} | path]
      |> Math.movement_duration(speed)
      |> Kernel.*(1_000)
      |> trunc()
      |> max(1)

    start_time = current_time_ms()
    internal = %{internal | movement_start_time: start_time, movement_start_position: {x0, y0, z0}}

    movement_block = %{mb | spline_nodes: path, duration: duration, time_passed: 0, spline_flags: 0x100}

    %{entity | movement_block: movement_block, internal: internal}
    |> increment_spline_id()
  end

  def move_to(state, {x, y, z}) do
    state = start_move_to(state, {x, y, z})

    # TODO: could be done in handle_continue instead?
    # treat more like a side effect?
    SmsgMonsterMove.build(state)
    |> World.broadcast_packet(state)

    state
  end

  def wander(%{internal: %Internal{spawn_distance: spawn_distance, map: map, initial_position: {xi, yi, zi}}} = state) do
    case Pathfinding.find_random_point_around_circle(map, {xi, yi, zi}, spawn_distance) do
      nil -> state
      {x, y, z} -> move_to(state, {x, y, z})
    end
  end

  def wander_delay(%{movement_block: %MovementBlock{duration: duration}}) do
    duration = duration || 0
    duration + :rand.uniform(6_000) + 4_000
  end

  def follow_waypoint_route(%{internal: %Internal{waypoint_route: %WaypointRoute{} = route}} = state) do
    %Waypoint{position: {x, y, z, o}} = WaypointRoute.destination_waypoint(route)

    state
    |> move_to({x, y, z})
    |> set_orientation(o)
    |> increment_waypoint()
  end

  def follow_waypoint_route_delay(%{
        movement_block: %MovementBlock{duration: duration},
        internal: %Internal{waypoint_route: route}
      }) do
    duration = duration || 0
    wait_time = WaypointRoute.destination_waypoint(route).wait_time || 0
    duration + wait_time
  end

  defp update_position_from_spline(
         %{
           movement_block: %MovementBlock{duration: duration, spline_nodes: spline_nodes, position: {_, _, _, o}} = mb,
           internal: %Internal{map: map, movement_start_time: start_time, movement_start_position: start_position}
         } = entity
       )
       when is_integer(duration) and duration > 0 and not is_nil(start_time) and not is_nil(start_position) do
    now = current_time_ms()
    elapsed = max(now - start_time, 0)
    elapsed = min(elapsed, duration)

    path = [start_position | spline_nodes]
    total_distance = path_length(path)

    {x, y, z} =
      if total_distance <= 0 do
        List.last(path)
      else
        distance_travelled = total_distance * elapsed / duration
        point_along_path(map, path, distance_travelled)
      end

    movement_block = %{mb | position: {x, y, z, o}, time_passed: elapsed}
    entity = %{entity | movement_block: movement_block}

    if elapsed >= duration do
      finalize_movement(entity)
    else
      entity
    end
  end

  defp update_position_from_spline(entity), do: finalize_movement(entity)

  defp finalize_movement(
         %{
           movement_block: %MovementBlock{spline_nodes: spline_nodes, position: {_, _, _, o}} = mb,
           internal: %Internal{} = internal
         } = entity
       ) do
    case spline_nodes do
      nil ->
        entity

      [] ->
        entity

      _ ->
        {x, y, z} = List.last(spline_nodes)

        movement_block = %{
          mb
          | position: {x, y, z, o},
            spline_nodes: [],
            movement_flags: 0,
            time_passed: mb.duration,
            spline_flags: 0
        }

        internal = %{internal | movement_start_time: nil, movement_start_position: nil}
        %{entity | movement_block: movement_block, internal: internal}
    end
  end

  defp path_length(points) when is_list(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [start, finish], acc -> acc + segment_distance(start, finish) end)
  end

  defp segment_distance(start, finish) do
    Math.movement_duration(start, finish, 1.0)
  end

  defp point_along_path(map, [start | rest], distance) do
    case Enum.reduce_while(rest, {start, distance}, fn node, {prev, remaining} ->
           segment_distance = segment_distance(prev, node)

           if remaining <= segment_distance do
             point = Pathfinding.find_point_between_points(map, prev, node, remaining) || node
             {:halt, {:point, point}}
           else
             {:cont, {node, remaining - segment_distance}}
           end
         end) do
      {:point, point} ->
        point

      {last, _remaining} ->
        last
    end
  end

  defp current_time_ms do
    System.monotonic_time(:millisecond)
  end

  defp increment_waypoint(%{internal: %Internal{waypoint_route: route} = internal} = state) do
    route = WaypointRoute.increment_waypoint(route)
    %{state | internal: %{internal | waypoint_route: route}}
  end

  defp set_orientation(%{movement_block: %MovementBlock{position: {x, y, z, _o}}} = entity, o) do
    %{entity | movement_block: %{entity.movement_block | position: {x, y, z, o}}}
  end
end
