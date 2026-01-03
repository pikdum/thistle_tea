defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash

  @chase_first_delay 500
  @chase_tick_delay 100

  # TODO: a lot of these should be pulled from entity data
  @chase_stop_distance 1.5
  @chase_repath_threshold 2.0

  @chase_attacker_radius 10.0
  @target_radius_guess 0.9
  @default_bounding_radius 0.6
  @attack_angle_scale 0.6

  defp dead?(%Mob{unit: %Unit{health: health}}, _blackboard) when is_number(health) do
    health <= 0
  end

  defp dead?(%Mob{}, _blackboard) do
    false
  end

  defp has_waypoints?(%Mob{internal: %Internal{waypoint_route: %WaypointRoute{}}}, _blackboard) do
    true
  end

  defp has_waypoints?(%Mob{}, _blackboard) do
    false
  end

  defp can_wander?(%Mob{internal: %Internal{movement_type: 1}}, _blackboard) do
    true
  end

  defp can_wander?(%Mob{}, _blackboard) do
    false
  end

  defp in_combat?(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: target}}, _blackboard)
       when is_integer(target) and target > 0 do
    true
  end

  defp in_combat?(%Mob{}, _blackboard) do
    false
  end

  defp chase_target(%Mob{} = state, blackboard) do
    state = set_running(state, true)
    target = state.unit.target

    case World.target_position(target) do
      {map, x, y, z} when map == state.internal.map ->
        distance = World.distance_to_guid(state, target)

        if is_number(distance) and in_combat_range?(state, distance) do
          blackboard = Blackboard.clear_chase(blackboard)
          blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, combat_wait_delay())
          {:running, state, blackboard}
        else
          if Blackboard.ready_for?(blackboard, :next_chase_at) do
            {state, blackboard} = maybe_repath_chase(state, blackboard, {x, y, z}, target)
            {delay, blackboard} = chase_delay(blackboard)
            blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, delay)
            {:running, state, blackboard}
          else
            {:running, state, blackboard}
          end
        end

      _ ->
        blackboard = Blackboard.clear_chase(blackboard)
        blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, idle_delay())
        {:running, state, blackboard}
    end
  end

  defp chase_delay(%Blackboard{chase_started: true} = blackboard) do
    {@chase_tick_delay, blackboard}
  end

  defp chase_delay(%Blackboard{} = blackboard) do
    {@chase_first_delay, %{blackboard | chase_started: true}}
  end

  defp maybe_repath_chase(%Mob{} = state, %Blackboard{} = blackboard, target_pos, target_guid) do
    target_moved = target_moved_enough?(blackboard, target_pos)
    should_repath = target_moved or not Movement.is_moving?(state)

    if should_repath do
      destination = chase_destination(state, target_pos)
      state = Movement.move_to(state, destination, face_target: target_guid)
      {state, %{blackboard | last_target_pos: target_pos}}
    else
      {state, blackboard}
    end
  end

  defp chase_destination(
         %Mob{
           object: %{guid: guid},
           movement_block: %MovementBlock{position: {mx, my, mz, _o}},
           internal: %Internal{map: map},
           unit: %Unit{bounding_radius: mob_radius}
         },
         {tx, ty, tz}
       ) do
    base_angle = base_chase_angle({mx, my}, {tx, ty})
    attacker_count = nearby_attacker_count(map, guid, {tx, ty, tz}, {mx, my, mz})

    mob_radius =
      case mob_radius do
        value when is_number(value) -> value
        _ -> @default_bounding_radius
      end

    size_factor = max(@target_radius_guess + mob_radius, @default_bounding_radius)
    angle_offset = attack_angle_offset(attacker_count, size_factor)
    angle = base_angle + angle_offset

    {
      tx + :math.cos(angle) * @chase_stop_distance,
      ty + :math.sin(angle) * @chase_stop_distance,
      tz
    }
  end

  defp base_chase_angle({mx, my}, {tx, ty}) do
    dx = mx - tx
    dy = my - ty

    if abs(dx) < 1.0e-4 and abs(dy) < 1.0e-4 do
      :rand.uniform() * :math.pi() * 2.0
    else
      :math.atan2(dy, dx)
    end
  end

  # TODO: this should actually be the count of mobs attacking the target, but we don't have that handy yet
  defp nearby_attacker_count(map, guid, {tx, ty, tz}, {mx, my, mz}) do
    target_count = count_nearby_mobs(map, guid, {tx, ty, tz})
    mob_count = count_nearby_mobs(map, guid, {mx, my, mz})
    max(target_count, mob_count)
  end

  defp count_nearby_mobs(map, guid, {x, y, z}) do
    SpatialHash.query(:mobs, map, x, y, z, @chase_attacker_radius)
    |> Enum.count(fn {mob_guid, _pid, _distance} -> mob_guid != guid end)
  end

  defp attack_angle_offset(attacker_count, size_factor) when attacker_count > 0 do
    spread = :math.pi() / 2.0 - :math.pi() * :rand.uniform()
    spread * (attacker_count / size_factor) * @attack_angle_scale
  end

  defp attack_angle_offset(_attacker_count, _size_factor), do: 0.0

  defp target_moved_enough?(%Blackboard{last_target_pos: {lx, ly, lz}}, {x, y, z}) do
    SpatialHash.distance({lx, ly, lz}, {x, y, z}) >= @chase_repath_threshold
  end

  defp target_moved_enough?(%Blackboard{}, {_x, _y, _z}) do
    true
  end

  defp wait_until_wander_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    if Blackboard.ready_for?(blackboard, :next_wander_at) do
      {:success, state, blackboard}
    else
      {:running, state, blackboard}
    end
  end

  defp wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    if Blackboard.ready_for?(blackboard, :next_waypoint_at) do
      {:success, state, blackboard}
    else
      {:running, state, blackboard}
    end
  end

  defp pick_wander_point(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)

    if blackboard.target do
      {:success, state, blackboard}
    else
      case Pathfinding.find_random_point_around_circle(
             state.internal.map,
             state.internal.initial_position,
             state.internal.spawn_distance
           ) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, idle_delay())
          {:running, state, Blackboard.clear_move_target(blackboard)}

        {x, y, z} ->
          {:success, state, %{blackboard | target: {x, y, z}}}
      end
    end
  end

  defp pick_waypoint(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)

    if blackboard.target do
      {:success, state, blackboard}
    else
      case waypoint_destination(state) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, idle_delay())
          {:running, state, Blackboard.clear_waypoint(blackboard)}

        %{position: {x, y, z, o}, wait_time: wait_time} ->
          blackboard = %{
            blackboard
            | target: {x, y, z},
              orientation: o,
              wait_time: wait_time || 0
          }

          {:success, state, blackboard}
      end
    end
  end

  defp move_to_target(%Mob{} = state, %Blackboard{} = blackboard) do
    case blackboard.target do
      {x, y, z} = target ->
        if blackboard.move_target == target do
          {:success, state, blackboard}
        else
          state = Movement.move_to(state, {x, y, z})
          {:success, state, %{blackboard | move_target: target}}
        end

      _ ->
        {:failure, state, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp wait_for_arrival(%Mob{} = state, %Blackboard{} = blackboard) do
    if Movement.is_moving?(state) do
      {:running, state, blackboard}
    else
      {:success, state, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp apply_waypoint(%Mob{} = state, %Blackboard{} = blackboard) do
    state =
      case blackboard.orientation do
        o when is_number(o) -> set_orientation(state, o)
        _ -> state
      end

    state = increment_waypoint(state)
    {:success, state, blackboard}
  end

  defp set_next_waypoint_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    wait_time = blackboard.wait_time || 0
    blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, wait_time)
    {:success, state, Blackboard.clear_waypoint(blackboard)}
  end

  defp set_next_wander_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, wander_wait_delay())
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  defp idle(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)
    {:running, state, blackboard}
  end

  defp idle_dead(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)
    {:running, state, blackboard}
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

  defp in_combat_range?(%Mob{unit: %Unit{combat_reach: combat_reach}}, distance)
       when is_number(distance) and is_number(combat_reach) do
    distance <= max(combat_reach, 2.0)
  end

  defp in_combat_range?(%Mob{}, distance) when is_number(distance) do
    distance <= 2.0
  end

  defp idle_delay do
    :rand.uniform(4_000) + 2_000
  end

  defp wander_wait_delay do
    :rand.uniform(6_000) + 4_000
  end

  defp combat_wait_delay do
    :rand.uniform(1_000) + 500
  end

  defp set_running(%Mob{internal: %Internal{} = internal} = state, running) when is_boolean(running) do
    %{state | internal: %{internal | running: running}}
  end

  def tree do
    build_tree()
  end

  defp build_tree do
    BT.selector([
      BT.sequence([
        BT.condition(&dead?/2),
        BT.action(&idle_dead/2)
      ]),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.action(&chase_target/2)
      ]),
      BT.sequence([
        BT.condition(&has_waypoints?/2),
        BT.action(&wait_until_waypoint_ready/2),
        BT.action(&pick_waypoint/2),
        BT.action(&move_to_target/2),
        BT.action(&wait_for_arrival/2),
        BT.action(&apply_waypoint/2),
        BT.action(&set_next_waypoint_wait/2)
      ]),
      BT.sequence([
        BT.condition(&can_wander?/2),
        BT.action(&wait_until_wander_ready/2),
        BT.action(&pick_wander_point/2),
        BT.action(&move_to_target/2),
        BT.action(&wait_for_arrival/2),
        BT.action(&set_next_wander_wait/2)
      ]),
      BT.action(&idle/2)
    ])
  end
end
