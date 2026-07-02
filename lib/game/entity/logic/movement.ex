defmodule ThistleTea.Game.Entity.Logic.Movement do
  @moduledoc """
  Pure spline-movement state for server-driven entities: starting and halting
  moves, interpolating the current position along the active path, remaining
  move duration, and root/blocked checks.
  """
  import Bitwise, only: [&&&: 2, bnot: 1, bor: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash

  @max_u32 0xFFFFFFFF
  @movement_flag_forward 0x00000001
  @movement_flag_walk_mode 0x00000100
  @movement_flag_spline_enabled 0x00400000
  @movement_flag_root 0x08000000
  @spline_flag_runmode 0x00000100

  def increment_spline_id(%{internal: %Internal{spline_id: spline_id} = internal} = entity) do
    new_spline_id = increment_spline_id(spline_id)
    %{entity | internal: %{internal | spline_id: new_spline_id}}
  end

  def increment_spline_id(id) when is_integer(id) do
    rem(id, @max_u32) + 1
  end

  def moving?(%{internal: %Internal{movement_start_time: nil}}, _now), do: false

  def moving?(
        %{movement_block: %MovementBlock{duration: duration}, internal: %Internal{movement_start_time: start_time}},
        now
      )
      when is_integer(duration) and is_integer(start_time) and is_integer(now) and duration > 0 do
    now <= start_time + duration
  end

  def moving?(_entity, _now), do: false

  def remaining_move_duration(
        %{internal: %Internal{movement_start_time: start_time}, movement_block: %MovementBlock{duration: duration}},
        now
      )
      when is_integer(start_time) and is_integer(duration) and is_integer(now) and duration > 0 do
    max(start_time + duration - now, 0)
  end

  def remaining_move_duration(_entity, _now), do: 0

  def next_spatial_update_delay(
        %{
          internal: %Internal{map: map, movement_start_time: start_time, movement_start_position: start_position},
          movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
        } = entity,
        now
      )
      when is_integer(map) and is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and
             spline_nodes != [] and is_integer(duration) and duration > 0 and is_integer(now) do
    if moving?(entity, now) do
      remaining_delay = max(remaining_move_duration(entity, now), 1)
      next_spatial_update_delay(map, start_position, spline_nodes, start_time, duration, now, remaining_delay)
    else
      0
    end
  end

  def next_spatial_update_delay(_entity, _now), do: 0

  defp next_spatial_update_delay(map, start_position, spline_nodes, start_time, duration, now, remaining_delay) do
    path = [start_position | spline_nodes]
    total_distance = path_length(path)

    if total_distance <= 0 do
      remaining_delay
    else
      elapsed = min(max(now - start_time, 0), duration)
      current_cell = cell_at(map, start_position, spline_nodes, duration, elapsed)
      travelled = total_distance * elapsed / duration
      boundary_delay(path, travelled, map, current_cell, duration, total_distance, remaining_delay)
    end
  end

  defp cell_at(map, start_position, spline_nodes, duration, elapsed) do
    {x, y, z} = position_at(start_position, spline_nodes, duration, elapsed)
    SpatialHash.cell(map, x, y, z)
  end

  defp boundary_delay(path, travelled, map, current_cell, duration, total_distance, remaining_delay) do
    case distance_to_leave_cell(path, travelled, map, current_cell) do
      nil -> remaining_delay
      distance -> min(max(ceil(distance * duration / total_distance), 1), remaining_delay)
    end
  end

  def time_to_within(
        %{
          internal: %Internal{movement_start_time: start_time, movement_start_position: start_position},
          movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
        } = entity,
        {tx, ty},
        radius,
        now
      )
      when is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and
             is_integer(duration) and duration > 0 and is_number(radius) and is_integer(now) do
    if moving?(entity, now) do
      contact_delay(entity, {tx, ty}, radius, now)
    end
  end

  def time_to_within(_entity, _point, _radius, _now), do: nil

  defp contact_delay(
         %{
           internal: %Internal{movement_start_time: start_time, movement_start_position: start_position},
           movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
         } = entity,
         center,
         radius,
         now
       ) do
    path = [start_position | spline_nodes]
    total_distance = path_length(path)

    if total_distance > 0 do
      elapsed = min(max(now - start_time, 0), duration)
      travelled = total_distance * elapsed / duration
      contact_delay_at(entity, path, travelled, center, radius, total_distance, now)
    end
  end

  defp contact_delay_at(
         %{movement_block: %MovementBlock{duration: duration}} = entity,
         path,
         travelled,
         center,
         radius,
         total_distance,
         now
       ) do
    case distance_to_within(path, travelled, center, radius) do
      nil -> nil
      distance -> min(max(ceil(distance * duration / total_distance), 1), remaining_move_duration(entity, now))
    end
  end

  def sync_position(%{movement_block: %MovementBlock{spline_nodes: spline_nodes}} = entity, _now)
      when spline_nodes in [nil, []] do
    entity
  end

  def sync_position(%{movement_block: %MovementBlock{}, internal: %Internal{}} = entity, now) when is_integer(now) do
    if moving?(entity, now) do
      update_position_from_spline(entity, now)
    else
      finalize_movement(entity)
    end
  end

  def start_move_to(entity, {x, y, z}, now) when is_integer(now) do
    entity = sync_position(entity, now)
    entity = increment_spline_id(entity)

    %{
      movement_block: %MovementBlock{walk_speed: walk_speed, position: {x0, y0, z0, _o}} = mb,
      internal: %Internal{map: map, running: running, spline_id: spline_id} = internal
    } = entity

    path = Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

    if is_nil(path) do
      # handles maps that haven't been built yet
      raise "No path found from #{inspect({x0, y0, z0})} to #{inspect({x, y, z})}"
    end

    speed = if running, do: mb.run_speed, else: walk_speed

    duration =
      [{x0, y0, z0} | path]
      |> Math.movement_duration(speed)
      |> Kernel.*(1_000)
      |> trunc()
      |> max(1)

    internal = %{internal | movement_start_time: now, movement_start_position: {x0, y0, z0}}

    movement_block = %{
      mb
      | spline_nodes: path,
        duration: duration,
        time_passed: 0,
        movement_flags: movement_flags(mb.movement_flags, running),
        spline_flags: spline_flags(running),
        spline_id: spline_id,
        spline_start_position: {x0, y0, z0}
    }

    %{entity | movement_block: movement_block, internal: internal}
  end

  def resume_spline(
        %{
          internal: %Internal{movement_start_time: start_time, movement_start_position: start_position},
          movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
        } = entity,
        now
      )
      when is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and
             is_integer(duration) and duration > 0 and is_integer(now) do
    if moving?(entity, now) do
      remaining_spline_entity(entity, now)
    end
  end

  def resume_spline(_entity, _now), do: nil

  defp remaining_spline_entity(
         %{
           internal: %Internal{movement_start_time: start_time, movement_start_position: start_position},
           movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration, position: {_, _, _, o}} = mb
         } = entity,
         now
       ) do
    elapsed = min(max(now - start_time, 0), duration)
    path = [start_position | spline_nodes]
    travelled = path_length(path) * elapsed / duration
    {x, y, z} = position_at(start_position, spline_nodes, duration, elapsed)

    case nodes_after(path, travelled) do
      [] ->
        nil

      remaining_nodes ->
        movement_block = %{
          mb
          | position: {x, y, z, o},
            spline_nodes: remaining_nodes,
            duration: max(remaining_move_duration(entity, now), 1)
        }

        %{entity | movement_block: movement_block}
    end
  end

  defp nodes_after([start | rest], travelled) do
    rest
    |> Enum.reduce({start, 0.0, []}, fn node, {prev, distance_acc, kept} ->
      segment_end = distance_acc + segment_distance(prev, node)
      kept = if segment_end > travelled, do: [node | kept], else: kept
      {node, segment_end, kept}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  def move_to(%{movement_block: %MovementBlock{movement_flags: flags}} = state, _destination, _opts, _now)
      when is_integer(flags) and (flags &&& @movement_flag_root) > 0 do
    state
  end

  def move_to(state, {x, y, z}, opts, now) when is_integer(now) do
    state
    |> start_move_to({x, y, z}, now)
    |> Event.enqueue(Event.monster_move(opts))
  end

  def halt(%{movement_block: %MovementBlock{} = mb, internal: %Internal{} = internal} = entity, now)
      when is_integer(now) do
    entity = sync_position(entity, now)

    movement_block = %{
      entity.movement_block
      | spline_nodes: [],
        spline_flags: 0,
        spline_id: nil,
        spline_start_position: nil,
        duration: 0,
        time_passed: 0,
        movement_flags: clear_motion_flags(mb.movement_flags)
    }

    internal = %{internal | movement_start_time: nil, movement_start_position: nil}
    %{entity | movement_block: movement_block, internal: internal}
  end

  def blocked?(%{movement_block: %MovementBlock{movement_flags: flags}})
      when is_integer(flags) and (flags &&& @movement_flag_root) > 0 do
    true
  end

  def blocked?(_entity), do: false

  defp clear_motion_flags(flags) when is_integer(flags) do
    flags &&& bnot(bor(@movement_flag_forward, @movement_flag_spline_enabled))
  end

  defp clear_motion_flags(_flags), do: 0

  defp update_position_from_spline(
         %{
           movement_block: %MovementBlock{duration: duration, spline_nodes: spline_nodes, position: {_, _, _, o}} = mb,
           internal: %Internal{map: map, movement_start_time: start_time, movement_start_position: start_position}
         } = entity,
         now
       )
       when is_integer(duration) and duration > 0 and not is_nil(start_time) and not is_nil(start_position) do
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

  defp update_position_from_spline(entity, _now), do: finalize_movement(entity)

  defp movement_flags(flags, running) do
    flags = flags || 0
    flags = bor(flags, bor(@movement_flag_forward, @movement_flag_spline_enabled))

    if running do
      flags &&& bnot(@movement_flag_walk_mode)
    else
      bor(flags, @movement_flag_walk_mode)
    end
  end

  defp spline_flags(true), do: @spline_flag_runmode
  defp spline_flags(false), do: 0

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
            spline_flags: 0,
            spline_id: nil,
            spline_start_position: nil
        }

        internal = %{internal | movement_start_time: nil, movement_start_position: nil}
        %{entity | movement_block: movement_block, internal: internal}
    end
  end

  def position_at(start_position, spline_nodes, duration, elapsed)
      when is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and is_integer(duration) and
             duration > 0 do
    path = [start_position | spline_nodes]
    total_distance = path_length(path)

    if total_distance <= 0 do
      List.last(path)
    else
      elapsed = min(max(elapsed, 0), duration)
      lerp_along_path(path, total_distance * elapsed / duration)
    end
  end

  def position_at(start_position, _spline_nodes, _duration, _elapsed), do: start_position

  defp lerp_along_path([start | rest], distance) do
    case Enum.reduce_while(rest, {start, distance}, fn node, {prev, remaining} ->
           segment_distance = segment_distance(prev, node)

           # credo:disable-for-next-line Credo.Check.Refactor.Nesting
           if remaining <= segment_distance do
             {:halt, {:point, lerp_point(prev, node, segment_distance, remaining)}}
           else
             {:cont, {node, remaining - segment_distance}}
           end
         end) do
      {:point, point} -> point
      {last, _remaining} -> last
    end
  end

  defp lerp_point({x1, y1, z1}, {x2, y2, z2}, segment_distance, remaining) when segment_distance > 0 do
    t = remaining / segment_distance
    {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t}
  end

  defp lerp_point(_start, finish, _segment_distance, _remaining), do: finish

  defp distance_to_within([start | rest], travelled, center, radius) do
    rest
    |> Enum.reduce_while({start, 0.0}, &reduce_contact_segment(&1, &2, travelled, center, radius))
    |> case do
      {_finish, _distance_acc} -> nil
      distance -> distance
    end
  end

  defp reduce_contact_segment(finish, {prev, distance_acc}, travelled, center, radius) do
    segment_distance = segment_distance(prev, finish)
    segment_end = distance_acc + segment_distance

    cond do
      segment_distance <= 0 ->
        {:cont, {finish, distance_acc}}

      travelled >= segment_end ->
        {:cont, {finish, segment_end}}

      true ->
        offset = max(travelled - distance_acc, 0.0)
        segment_start = lerp_point(prev, finish, segment_distance, offset)
        remaining_segment_distance = segment_distance - offset
        contact_reduce_result(segment_start, finish, remaining_segment_distance, segment_end, travelled, center, radius)
    end
  end

  defp contact_reduce_result(segment_start, finish, remaining_segment_distance, segment_end, travelled, center, radius) do
    case contact_distance_on_segment(segment_start, finish, remaining_segment_distance, center, radius) do
      nil -> {:cont, {finish, segment_end}}
      distance -> {:halt, max(segment_end - remaining_segment_distance - travelled, 0.0) + distance}
    end
  end

  defp contact_distance_on_segment({x1, y1, _z1}, {x2, y2, _z2}, segment_length, {cx, cy}, radius) do
    fx = x1 - cx
    fy = y1 - cy

    if fx * fx + fy * fy <= radius * radius do
      0.0
    else
      contact_entry_distance(x2 - x1, y2 - y1, fx, fy, segment_length, radius)
    end
  end

  defp contact_entry_distance(dx, dy, fx, fy, segment_length, radius) do
    a = dx * dx + dy * dy
    b = 2.0 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - radius * radius
    discriminant = b * b - 4.0 * a * c

    if a > 0 and discriminant >= 0 do
      t = (-b - :math.sqrt(discriminant)) / (2.0 * a)
      if t >= 0.0 and t <= 1.0, do: t * segment_length
    end
  end

  defp distance_to_leave_cell([start | rest], travelled, map, cell) do
    rest
    |> Enum.reduce_while({start, 0.0}, &reduce_cell_boundary_segment(&1, &2, travelled, map, cell))
    |> case do
      {_finish, _distance_acc} -> nil
      distance -> distance
    end
  end

  defp reduce_cell_boundary_segment(finish, {prev, distance_acc}, travelled, map, cell) do
    segment_distance = segment_distance(prev, finish)
    segment_end = distance_acc + segment_distance

    cond do
      segment_distance <= 0 ->
        {:cont, {finish, distance_acc}}

      travelled >= segment_end ->
        {:cont, {finish, segment_end}}

      true ->
        offset = max(travelled - distance_acc, 0.0)
        segment_start = lerp_point(prev, finish, segment_distance, offset)
        remaining_segment_distance = segment_distance - offset
        cell_boundary_reduce_result(map, cell, segment_start, finish, remaining_segment_distance, segment_end)
    end
  end

  defp cell_boundary_reduce_result(map, cell, segment_start, finish, remaining_segment_distance, segment_end) do
    case distance_to_leave_cell_segment(map, cell, segment_start, finish, remaining_segment_distance) do
      nil -> {:cont, {finish, segment_end}}
      distance -> {:halt, distance}
    end
  end

  defp distance_to_leave_cell_segment(map, cell, {x1, y1, _z1}, {x2, y2, _z2}, distance) do
    cond do
      SpatialHash.cell(map, x1, y1, 0.0) != cell ->
        0.0

      SpatialHash.cell(map, x2, y2, 0.0) == cell ->
        nil

      true ->
        cell_boundary_distance(cell, x1, y1, x2 - x1, y2 - y1, distance)
    end
  end

  defp cell_boundary_distance(cell, x, y, dx, dy, distance) do
    {{x_min, x_max}, {y_min, y_max}} = SpatialHash.cell_bounds(cell)

    [boundary_fraction(x, dx, x_min, x_max), boundary_fraction(y, dy, y_min, y_max)]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn fraction -> fraction >= 0.0 and fraction <= 1.0 end)
    |> case do
      [] -> distance
      fractions -> Enum.min(fractions) * distance
    end
  end

  defp boundary_fraction(position, delta, _min_boundary, max_boundary) when delta > 0 do
    (max_boundary - position) / delta
  end

  defp boundary_fraction(position, delta, min_boundary, _max_boundary) when delta < 0 do
    (min_boundary - position) / delta
  end

  defp boundary_fraction(_position, _delta, _min_boundary, _max_boundary), do: nil

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

           # credo:disable-for-next-line Credo.Check.Refactor.Nesting
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
end
