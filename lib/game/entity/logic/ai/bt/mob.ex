defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @chase_tick_delay 100

  # TODO: a lot of these should be pulled from entity data
  @target_radius_guess 0.9
  @default_bounding_radius 0.6
  @attack_angle_scale 0.3

  def tree do
    BT.selector([
      BT.sequence([
        BT.condition(&tethering_to_spawn?/2),
        BT.action(&wait_for_arrival/2)
      ]),
      BT.sequence([
        BT.condition(&dead?/2),
        BT.action(&idle_dead/2)
      ]),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.action(&set_running_true/2),
        BT.selector([
          BT.sequence([
            BT.condition(&target_dead?/2),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&move_to_target/2)
          ]),
          BT.sequence([
            BT.condition(&should_tether?/2),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&move_to_target/2)
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/2),
            BT.condition(&in_combat_range?/2),
            BT.action(&melee_attack/2),
            BT.action(&combat_wait/2)
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/2),
            BT.condition(&chase_ready?/2),
            BT.action(&chase_repath_and_schedule/2)
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/2),
            BT.action(&wait_for_chase_tick/2)
          ]),
          BT.action(&clear_chase_and_idle/2)
        ])
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

  defp dead?(%Mob{} = state, _blackboard) do
    Core.dead?(state)
  end

  defp dead?(_state, _blackboard) do
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

  defp in_combat?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.in_combat?(state, blackboard)
  end

  defp set_running_true(%Mob{} = state, %Blackboard{} = blackboard) do
    {:success, set_running(state, true), blackboard}
  end

  defp should_tether?(%Mob{} = state, _blackboard) do
    Core.should_tether?(state)
  end

  defp target_dead?(%Mob{unit: %Unit{target: target}}, _blackboard) when is_integer(target) and target > 0 do
    case Metadata.query(target, [:alive?]) do
      %{alive?: false} -> true
      _ -> false
    end
  end

  defp target_dead?(_state, _blackboard) do
    false
  end

  defp tethering_to_spawn?(%Mob{internal: %Internal{initial_position: {x, y, z}}} = state, %Blackboard{
         move_target: {x, y, z}
       }) do
    Movement.is_moving?(state)
  end

  defp tethering_to_spawn?(_state, _blackboard) do
    false
  end

  defp set_tether_target(%Mob{internal: %Internal{initial_position: {x, y, z}}} = state, %Blackboard{} = blackboard) do
    {:success, state, %{blackboard | target: {x, y, z}}}
  end

  defp set_tether_target(%Mob{} = state, %Blackboard{} = blackboard) do
    {:failure, state, blackboard}
  end

  defp clear_combat(
         %Mob{unit: %Unit{max_health: max_health, target: target} = unit, internal: %Internal{} = internal} = state,
         %Blackboard{} = blackboard
       ) do
    decrement_attacker_count(target)
    health = if is_number(max_health), do: max_health, else: unit.health
    unit = %{unit | target: 0, health: health}
    internal = %{internal | in_combat: false}

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.clear_attack()

    state = %{state | unit: unit, internal: internal}

    state = Core.mark_broadcast_update(state)

    {:success, state, blackboard}
  end

  defp target_valid_same_map?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.target_valid_same_map?(state, blackboard)
  end

  defp in_combat_range?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.in_combat_range?(state, blackboard)
  end

  defp chase_ready?(_state, %Blackboard{} = blackboard) do
    Blackboard.ready_for?(blackboard, :next_chase_at)
  end

  defp combat_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, combat_wait_delay())

    {:running, state, blackboard}
  end

  defp melee_attack(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.melee_attack(state, blackboard)
  end

  defp chase_repath_and_schedule(%Mob{} = state, %Blackboard{} = blackboard) do
    target = state.unit.target

    case World.target_position(target) do
      {map, x, y, z} when map == state.internal.map ->
        {state, blackboard} = maybe_repath_chase(state, blackboard, {x, y, z}, target)
        blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, @chase_tick_delay)
        {:running, state, blackboard}

      _ ->
        clear_chase_and_idle(state, blackboard)
    end
  end

  defp wait_for_chase_tick(%Mob{} = state, %Blackboard{} = blackboard) do
    {:running, state, blackboard}
  end

  defp clear_chase_and_idle(%Mob{} = state, %Blackboard{} = blackboard) do
    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, idle_delay())

    {:running, state, blackboard}
  end

  defp maybe_repath_chase(%Mob{} = state, %Blackboard{} = blackboard, target_pos, target_guid) do
    target_moved = target_moved_enough?(blackboard, target_pos, target_guid)
    should_repath = target_moved or not Movement.is_moving?(state)

    if should_repath do
      destination = chase_destination(state, target_pos, target_guid)
      state = Movement.move_to(state, destination, face_target: target_guid)
      {state, %{blackboard | last_target_pos: target_pos}}
    else
      {state, blackboard}
    end
  end

  defp chase_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}, unit: %Unit{bounding_radius: mob_radius}},
         {tx, ty, tz},
         target_guid
       ) do
    base_angle = base_chase_angle({mx, my}, {tx, ty})
    attacker_count = attacker_count(target_guid)
    chase_distance = chase_stop_distance(target_guid)

    mob_radius =
      case mob_radius do
        value when is_number(value) -> value
        _ -> @default_bounding_radius
      end

    size_factor = max(@target_radius_guess + mob_radius, @default_bounding_radius)
    angle_offset = attack_angle_offset(attacker_count, size_factor)
    angle = base_angle + angle_offset

    {
      tx + :math.cos(angle) * chase_distance,
      ty + :math.sin(angle) * chase_distance,
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

  defp attacker_count(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:attacker_count]) do
      %{attacker_count: count} when is_number(count) and count > 0 -> count
      _ -> 0
    end
  end

  defp attacker_count(_target_guid), do: 0

  defp decrement_attacker_count(target) when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
  end

  defp decrement_attacker_count(_target), do: :ok

  defp attack_angle_offset(attacker_count, size_factor) when attacker_count > 0 do
    spread = :math.pi() / 2.0 - :math.pi() * :rand.uniform()
    spread * (attacker_count / size_factor) * @attack_angle_scale
  end

  defp attack_angle_offset(_attacker_count, _size_factor), do: 0.0

  defp target_moved_enough?(%Blackboard{last_target_pos: {lx, ly, lz}}, {tx, ty, tz}, target_guid) do
    threshold = chase_repath_distance(target_guid)
    planar_distance({lx, ly, lz}, {tx, ty, tz}) > threshold
  end

  defp target_moved_enough?(%Blackboard{}, {_x, _y, _z}, _target_guid) do
    true
  end

  defp planar_distance({x1, y1, _z1}, {x2, y2, _z2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  defp chase_repath_distance(target_guid) do
    combat_reach = target_combat_reach(target_guid)
    bounding_radius = target_bounding_radius(target_guid)
    max(combat_reach * 0.75 - bounding_radius, 0.0)
  end

  defp chase_stop_distance(target_guid) do
    combat_reach = target_combat_reach(target_guid)
    max(combat_reach * 0.5, 0.0)
  end

  defp target_combat_reach(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:combat_reach]) do
      %{combat_reach: combat_reach} when is_number(combat_reach) -> combat_reach
      _ -> Unit.default_combat_reach()
    end
  end

  defp target_combat_reach(_target_guid), do: Unit.default_combat_reach()

  defp target_bounding_radius(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:bounding_radius]) do
      %{bounding_radius: bounding_radius} when is_number(bounding_radius) -> bounding_radius
      _ -> Unit.default_bounding_radius()
    end
  end

  defp target_bounding_radius(_target_guid), do: Unit.default_bounding_radius()

  defp wait_until_wander_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    if Blackboard.ready_for?(blackboard, :next_wander_at) do
      {:success, state, blackboard}
    else
      delay_ms = Blackboard.delay_until(blackboard, :next_wander_at)
      {{:running, delay_ms}, state, blackboard}
    end
  end

  defp wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    if Blackboard.ready_for?(blackboard, :next_waypoint_at) do
      {:success, state, blackboard}
    else
      delay_ms = Blackboard.delay_until(blackboard, :next_waypoint_at)
      {{:running, delay_ms}, state, blackboard}
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
      delay_ms = Movement.remaining_move_duration(state)
      {{:running, delay_ms}, state, blackboard}
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
end
