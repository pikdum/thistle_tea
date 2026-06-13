defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob do
  @moduledoc """
  The mob behavior tree: aggro checks, chasing and melee combat, tethering
  back to spawn, and idle wandering or waypoint-route movement.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.Regen, as: RegenLogic
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @chase_tick_delay 1_000

  # TODO: a lot of these should be pulled from entity data
  @target_radius_guess 0.9
  @default_bounding_radius 0.6
  @attack_angle_scale 0.3

  @base_aggro_radius 18.0
  @max_level_aggro_bonus 25
  @min_aggro_radius 5.0
  @max_aggro_radius @base_aggro_radius + @max_level_aggro_bonus
  @aggro_check_delay 5_000
  @dead_idle_delay 1_000
  @blocked_retry_delay 1_000

  def max_aggro_radius, do: @max_aggro_radius

  def tree do
    BT.selector([
      AuraBT.tick_step(),
      RegenBT.tick_step(),
      BT.sequence([
        BT.condition(&tethering_to_spawn?/2),
        BT.action(&wait_for_arrival/2)
      ]),
      BT.sequence([
        BT.condition(&dead?/2),
        BT.action(&idle_dead/2)
      ]),
      BT.sequence([
        BT.condition(&stunned?/2),
        BT.action(&idle_stunned/2)
      ]),
      BT.sequence([
        BT.condition(&confused?/2),
        BT.action(&wait_until_confused_wander_ready/2),
        BT.action(&pick_confused_point/2),
        BT.action(&move_to_target/2),
        BT.action(&wait_for_arrival/2),
        BT.action(&set_next_confused_wait/2)
      ]),
      BT.sequence([
        BT.condition(&aggro_check_ready?/2),
        BT.condition(&not_in_combat?/2),
        BT.action(&try_aggro/2)
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
            BT.action(&heal_to_full/2),
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

  defp has_waypoints?(%Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{}}}}, _blackboard) do
    true
  end

  defp has_waypoints?(%Mob{}, _blackboard) do
    false
  end

  defp can_wander?(%Mob{internal: %Internal{spawn: %Spawn{movement_type: 1}}}, _blackboard) do
    true
  end

  defp can_wander?(%Mob{}, _blackboard) do
    false
  end

  @confused_wander_radius 5.0

  defp confused?(%Mob{} = state, _blackboard) do
    AuraLogic.has_aura?(state, :mod_confuse) or AuraLogic.has_aura?(state, :mod_fear)
  end

  defp confused?(_state, _blackboard), do: false

  defp stunned?(%Mob{} = state, _blackboard) do
    AuraLogic.has_aura?(state, :mod_stun)
  end

  defp stunned?(_state, _blackboard), do: false

  defp idle_stunned(%Mob{} = state, %Blackboard{} = blackboard) do
    idle_stunned(state, blackboard, Time.now())
  end

  defp idle_stunned(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    state = set_running(state, false)
    blackboard = Blackboard.clear_move_target(blackboard)
    {BT.running(passive_delay(state, blackboard, now, @dead_idle_delay), :stunned), state, blackboard}
  end

  defp wait_until_confused_wander_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    now = Time.now()

    if Blackboard.ready_for?(blackboard, :next_confused_at, now) do
      {:success, state, blackboard}
    else
      delay_ms = Blackboard.delay_until(blackboard, :next_confused_at, now)
      {BT.running(delay_ms, :confused_wander), state, blackboard}
    end
  end

  defp pick_confused_point(
         %Mob{movement_block: %MovementBlock{position: {x, y, z, _o}}} = state,
         %Blackboard{} = blackboard
       ) do
    state = set_running(state, false)
    blackboard = ensure_confused_anchor(state, blackboard, {x, y, z})

    if blackboard.target do
      {:success, state, blackboard}
    else
      {_key, anchor} = blackboard.confused_anchor

      case Pathfinding.find_random_point_around_circle(state.internal.map, anchor, @confused_wander_radius) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_confused_at, confused_wait_delay(), Time.now())
          {:running, state, Blackboard.clear_move_target(blackboard)}

        {wx, wy, wz} ->
          {:success, state, %{blackboard | target: {wx, wy, wz}}}
      end
    end
  end

  defp ensure_confused_anchor(%Mob{} = state, %Blackboard{} = blackboard, current_position) do
    key = AuraLogic.confuse_anchor_key(state)

    case blackboard.confused_anchor do
      {^key, _anchor} ->
        blackboard

      _ ->
        %{Blackboard.clear_move_target(blackboard) | confused_anchor: {key, current_position}}
    end
  end

  defp set_next_confused_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    blackboard = Blackboard.put_next_at(blackboard, :next_confused_at, confused_wait_delay(), Time.now())
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  defp confused_wait_delay do
    :rand.uniform(1_000) + 500
  end

  defp in_combat?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.in_combat?(state, blackboard)
  end

  defp not_in_combat?(%Mob{} = state, %Blackboard{} = blackboard) do
    not in_combat?(state, blackboard)
  end

  defp aggro_check_ready?(state, %Blackboard{} = blackboard) do
    aggro_check_ready?(state, blackboard, Time.now())
  end

  def aggro_check_ready?(_state, %Blackboard{} = blackboard, now) when is_integer(now) do
    Blackboard.ready_for?(blackboard, :next_aggro_at, now)
  end

  defp try_aggro(%Mob{} = state, %Blackboard{} = blackboard) do
    now = Time.now()
    try_aggro(state, blackboard, now)
  end

  def try_aggro(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    blackboard = Blackboard.put_next_at(blackboard, :next_aggro_at, @aggro_check_delay, now)

    state =
      case pick_aggro_target(state) do
        nil -> state
        target_guid -> apply_aggro(state, target_guid, now)
      end

    {:failure, state, blackboard}
  end

  defp pick_aggro_target(%Mob{} = state) do
    if Hostility.can_initiate_attack?(state) do
      state
      |> nearby_aggro_candidates()
      |> Enum.filter(fn {guid, distance} -> aggro_candidate?(state, guid, distance) end)
      |> Enum.min_by(fn {_guid, distance} -> distance end, fn -> nil end)
      |> case do
        nil -> nil
        {guid, _distance} -> guid
      end
    end
  end

  defp nearby_aggro_candidates(%Mob{} = state) do
    World.nearby_players(state, @max_aggro_radius) ++ World.nearby_mobs(state, @max_aggro_radius)
  end

  defp aggro_candidate?(%Mob{} = state, guid, distance) when is_integer(guid) and is_number(distance) do
    Hostility.valid_hostile_target?(state, guid) and distance <= aggro_radius(state, guid)
  end

  defp aggro_candidate?(_state, _guid, _distance), do: false

  defp aggro_radius(%Mob{unit: %Unit{level: level}} = state, target_guid)
       when is_integer(level) and is_integer(target_guid) do
    target_level = target_level(target_guid)
    level_diff = max(target_level - level, -@max_level_aggro_bonus)
    max(@base_aggro_radius - level_diff + detect_range_modifier(state), @min_aggro_radius)
  end

  defp aggro_radius(%Mob{}, _target_guid), do: @base_aggro_radius

  defp detect_range_modifier(%Mob{} = state) do
    state
    |> AuraLogic.auras_of_type(:mod_detect_range)
    |> Enum.reduce(0, fn
      %{amount: amount}, acc when is_integer(amount) -> acc + amount
      _aura, acc -> acc
    end)
  end

  defp target_level(guid) when is_integer(guid) do
    case Metadata.query(guid, [:level]) do
      %{level: level} when is_integer(level) -> level
      _ -> 1
    end
  end

  defp apply_aggro(%Mob{unit: %Unit{} = unit, internal: %Internal{} = internal} = state, target_guid, now) do
    unit = %{unit | target: target_guid}
    internal = %{internal | in_combat: true, last_hostile_time: now}
    state = %{state | unit: unit, internal: internal}

    state
    |> Event.enqueue(Event.attacker_gained(target_guid))
    |> Core.mark_broadcast_update()
  end

  defp set_running_true(%Mob{} = state, %Blackboard{} = blackboard) do
    {:success, set_running(state, true), blackboard}
  end

  defp should_tether?(%Mob{} = state, blackboard) do
    should_tether?(state, blackboard, Time.now())
  end

  def should_tether?(%Mob{} = state, _blackboard, now) when is_integer(now) do
    Core.should_tether?(state, now)
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

  defp tethering_to_spawn?(
         %Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}} = state,
         %Blackboard{move_target: {x, y, z}} = blackboard
       ) do
    tethering_to_spawn?(state, blackboard, Time.now())
  end

  defp tethering_to_spawn?(_state, _blackboard) do
    false
  end

  def tethering_to_spawn?(
        %Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}} = state,
        %Blackboard{move_target: {x, y, z}},
        now
      )
      when is_integer(now) do
    Movement.moving?(state, now)
  end

  def tethering_to_spawn?(_state, _blackboard, _now), do: false

  defp set_tether_target(
         %Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}} = state,
         %Blackboard{} = blackboard
       ) do
    {:success, state, %{blackboard | target: {x, y, z}}}
  end

  defp set_tether_target(%Mob{} = state, %Blackboard{} = blackboard) do
    {:failure, state, blackboard}
  end

  @dynamic_flag_tapped 0x0004

  defp clear_combat(
         %Mob{unit: %Unit{target: target} = unit, internal: %Internal{} = internal} = state,
         %Blackboard{} = blackboard
       ) do
    unit = %{unit | target: 0, dynamic_flags: Bitwise.band(unit.dynamic_flags || 0, Bitwise.bnot(@dynamic_flag_tapped))}
    internal = %{internal | in_combat: false, loot: clear_tap(internal.loot)}

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.clear_attack()

    state = %{state | unit: unit, internal: internal}

    state =
      state
      |> Event.enqueue(clear_combat_events(target))
      |> Core.mark_broadcast_update()

    {:success, state, blackboard}
  end

  defp clear_combat_events(target) when is_integer(target) and target > 0 do
    [Event.attacker_lost(target), Event.tap_cleared()]
  end

  defp clear_combat_events(_target) do
    [Event.tap_cleared()]
  end

  defp clear_tap(%Loot{} = loot), do: %{loot | tapped_by: nil}
  defp clear_tap(loot), do: loot

  defp heal_to_full(
         %Mob{unit: %Unit{health: health, max_health: max_health} = unit} = state,
         %Blackboard{} = blackboard
       )
       when is_number(max_health) and is_number(health) and health < max_health do
    state =
      %{state | unit: %{unit | health: max_health}}
      |> Core.mark_broadcast_update()

    {:success, state, blackboard}
  end

  defp heal_to_full(state, %Blackboard{} = blackboard) do
    {:success, state, blackboard}
  end

  defp target_valid_same_map?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.target_valid_same_map?(state, blackboard)
  end

  defp in_combat_range?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.in_combat_range?(state, blackboard)
  end

  defp chase_ready?(state, %Blackboard{} = blackboard) do
    chase_ready?(state, blackboard, Time.now())
  end

  def chase_ready?(_state, %Blackboard{} = blackboard, now) when is_integer(now) do
    Blackboard.ready_for?(blackboard, :next_chase_at, now)
  end

  defp combat_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    combat_wait(state, blackboard, Time.now())
  end

  def combat_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    attack_delay = Blackboard.delay_until(blackboard, :next_attack_at, now)
    chase_delay = combat_chase_delay(state, attack_delay, now)

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, chase_delay, now)

    {reason, delay_ms} =
      [
        {:attack, attack_delay},
        {:chase, chase_delay},
        {:aura, aura_delay(state, now)},
        {:regen, regen_delay(state, blackboard, now)}
      ]
      |> soonest_wake(:chase, @chase_tick_delay)

    {BT.running(delay_ms, reason), state, blackboard}
  end

  defp melee_attack(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.melee_attack(state, blackboard)
  end

  defp chase_repath_and_schedule(%Mob{} = state, %Blackboard{} = blackboard) do
    target = state.unit.target
    now = Time.now()

    case World.target_position(target) do
      {map, x, y, z} when map == state.internal.map ->
        {state, blackboard} = maybe_repath_chase(state, blackboard, {x, y, z}, target, now)
        delay_ms = chase_delay(state, now)
        blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, delay_ms, now)
        {BT.running(delay_ms, :chase), state, blackboard}

      _ ->
        clear_chase_and_idle(state, blackboard)
    end
  end

  defp wait_for_chase_tick(%Mob{} = state, %Blackboard{} = blackboard) do
    wait_for_chase_tick(state, blackboard, Time.now())
  end

  def wait_for_chase_tick(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delay_ms = Blackboard.delay_until(blackboard, :next_chase_at, now)
    {BT.running(soonest_delay([delay_ms], @chase_tick_delay), :chase), state, blackboard}
  end

  defp clear_chase_and_idle(%Mob{} = state, %Blackboard{} = blackboard) do
    clear_chase_and_idle(state, blackboard, Time.now())
  end

  def clear_chase_and_idle(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delay_ms = idle_delay()

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, delay_ms, now)

    {BT.running(delay_ms, :idle), state, blackboard}
  end

  defp maybe_repath_chase(%Mob{} = state, %Blackboard{} = blackboard, target_pos, target_guid, now) do
    target_moved = target_moved_enough?(state, blackboard, target_pos, target_guid)
    should_repath = target_moved or not Movement.moving?(state, now)

    if should_repath do
      destination = chase_destination(state, target_pos, target_guid)
      state = Movement.move_to(state, destination, [face_target: target_guid], now)
      {state, %{blackboard | last_target_pos: target_pos}}
    else
      {state, blackboard}
    end
  end

  defp chase_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}, unit: %Unit{bounding_radius: mob_radius}} =
           state,
         {tx, ty, tz},
         target_guid
       ) do
    base_angle = base_chase_angle({mx, my}, {tx, ty})
    attacker_count = attacker_count(target_guid)
    chase_distance = CombatLogic.chase_target_distance(melee_reach_to(state, target_guid))

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

  defp attack_angle_offset(attacker_count, size_factor) when attacker_count > 0 do
    spread = :math.pi() / 2.0 - :math.pi() * :rand.uniform()
    spread * (attacker_count / size_factor) * @attack_angle_scale
  end

  defp attack_angle_offset(_attacker_count, _size_factor), do: 0.0

  defp target_moved_enough?(%Mob{} = state, %Blackboard{last_target_pos: {lx, ly, lz}}, {tx, ty, tz}, target_guid) do
    threshold = chase_repath_distance(state, target_guid)
    planar_distance({lx, ly, lz}, {tx, ty, tz}) > threshold
  end

  defp target_moved_enough?(%Mob{}, %Blackboard{}, {_x, _y, _z}, _target_guid) do
    true
  end

  defp planar_distance({x1, y1, _z1}, {x2, y2, _z2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  def chase_repath_distance(%Mob{} = state, target_guid) do
    CombatLogic.chase_rechase_distance(melee_reach_to(state, target_guid), target_bounding_radius(target_guid))
  end

  defp melee_reach_to(%Mob{} = state, target_guid) do
    CombatLogic.melee_reach(own_combat_reach(state), target_combat_reach(target_guid))
  end

  defp own_combat_reach(%Mob{unit: %Unit{combat_reach: reach}}) when is_number(reach) and reach > 0, do: reach
  defp own_combat_reach(%Mob{}), do: Unit.default_combat_reach()

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
    wait_until_wander_ready(state, blackboard, Time.now())
  end

  def wait_until_wander_ready(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_wander_at, now) do
      {:success, state, blackboard}
    else
      {reason, delay_ms} = idle_wake(state, blackboard, :next_wander_at, now, :wander)
      {BT.running(delay_ms, reason), state, blackboard}
    end
  end

  defp wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard) do
    wait_until_waypoint_ready(state, blackboard, Time.now())
  end

  def wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_waypoint_at, now) do
      {:success, state, blackboard}
    else
      {reason, delay_ms} = idle_wake(state, blackboard, :next_waypoint_at, now, :waypoint)
      {BT.running(delay_ms, reason), state, blackboard}
    end
  end

  defp pick_wander_point(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)

    if blackboard.target do
      {:success, state, blackboard}
    else
      case Pathfinding.find_random_point_around_circle(
             state.internal.map,
             state.internal.spawn.position,
             state.internal.spawn.distance
           ) do
        nil ->
          now = Time.now()
          blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, idle_delay(), now)
          blackboard = Blackboard.clear_move_target(blackboard)
          {reason, delay_ms} = idle_wake(state, blackboard, :next_wander_at, now, :wander)
          {BT.running(delay_ms, reason), state, blackboard}

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
          now = Time.now()
          blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, idle_delay(), now)
          blackboard = Blackboard.clear_waypoint(blackboard)
          {reason, delay_ms} = idle_wake(state, blackboard, :next_waypoint_at, now, :waypoint)
          {BT.running(delay_ms, reason), state, blackboard}

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
    move_to_target(state, blackboard, Time.now())
  end

  def move_to_target(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    case blackboard.target do
      {x, y, z} = target ->
        cond do
          Movement.blocked?(state) ->
            {BT.running(blocked_delay(state, now), :blocked), state, blackboard}

          blackboard.move_target == target ->
            {:success, state, blackboard}

          true ->
            state = Movement.move_to(state, {x, y, z}, [], now)
            {:success, state, %{blackboard | move_target: target}}
        end

      _ ->
        {:failure, state, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp wait_for_arrival(%Mob{} = state, %Blackboard{} = blackboard) do
    wait_for_arrival(state, blackboard, Time.now())
  end

  def wait_for_arrival(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Movement.moving?(state, now) do
      delay_ms = Movement.next_spatial_update_delay(state, now)
      {BT.running(delay_ms, :movement), state, blackboard}
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
    set_next_waypoint_wait(state, blackboard, Time.now())
  end

  def set_next_waypoint_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    wait_time = blackboard.wait_time || 0
    blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, wait_time, now)
    {:success, state, Blackboard.clear_waypoint(blackboard)}
  end

  defp set_next_wander_wait(%Mob{} = state, %Blackboard{} = blackboard) do
    set_next_wander_wait(state, blackboard, Time.now())
  end

  def set_next_wander_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, wander_wait_delay(), now)
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  defp idle(%Mob{} = state, %Blackboard{} = blackboard) do
    idle(state, blackboard, Time.now())
  end

  defp idle(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    state = set_running(state, false)
    {reason, delay_ms} = idle_wake(state, blackboard, now)
    {BT.running(delay_ms, reason), state, blackboard}
  end

  defp idle_dead(%Mob{} = state, %Blackboard{} = blackboard) do
    state = set_running(state, false)
    {BT.running(passive_delay(state, blackboard, Time.now(), @dead_idle_delay), :dead), state, blackboard}
  end

  defp waypoint_destination(%Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route}}}) do
    WaypointRoute.destination_waypoint(route)
  end

  defp waypoint_destination(%Mob{}) do
    nil
  end

  defp increment_waypoint(
         %Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route} = spawn_state} = internal} =
           state
       ) do
    route = WaypointRoute.increment_waypoint(route)
    %{state | internal: %{internal | spawn: %{spawn_state | waypoint_route: route}}}
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

  defp set_running(%Mob{internal: %Internal{} = internal} = state, running) when is_boolean(running) do
    %{state | internal: %{internal | running: running}}
  end

  defp idle_wake(%Mob{} = state, %Blackboard{} = blackboard, now) do
    idle_wake(state, blackboard, :next_aggro_at, now, :aggro)
  end

  defp idle_wake(%Mob{} = state, %Blackboard{} = blackboard, key, now, key_reason) do
    [
      {key_reason, Blackboard.delay_until(blackboard, key, now)},
      {:aggro, Blackboard.delay_until(blackboard, :next_aggro_at, now)},
      {:aura, aura_delay(state, now)},
      {:regen, regen_delay(state, blackboard, now)}
    ]
    |> soonest_wake(:aggro, @aggro_check_delay)
  end

  defp passive_delay(%Mob{} = state, %Blackboard{} = blackboard, now, fallback) do
    [
      aura_delay(state, now),
      regen_delay(state, blackboard, now)
    ]
    |> soonest_delay(fallback)
  end

  defp blocked_delay(%Mob{} = state, now) do
    soonest_delay([aura_delay(state, now)], @blocked_retry_delay)
  end

  defp chase_delay(%Mob{} = state, now) do
    if Movement.moving?(state, now) do
      min(Movement.remaining_move_duration(state, now), @chase_tick_delay)
    else
      @chase_tick_delay
    end
  end

  defp combat_chase_delay(%Mob{} = state, attack_delay, now) do
    cond do
      Movement.moving?(state, now) ->
        Movement.next_spatial_update_delay(state, now)

      is_integer(attack_delay) and attack_delay > 0 ->
        attack_delay

      true ->
        @chase_tick_delay
    end
  end

  defp aura_delay(%Mob{} = state, now) do
    case AuraLogic.next_event_at(state) do
      at when is_integer(at) -> at - now
      _ -> nil
    end
  end

  defp regen_delay(%Mob{} = state, %Blackboard{} = blackboard, now) do
    if RegenLogic.needs_regen?(state) do
      Blackboard.delay_until(blackboard, :next_regen_at, now)
    end
  end

  defp soonest_delay(delays, fallback) do
    delays
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.min(fn -> fallback end)
  end

  defp soonest_wake(wakes, fallback_reason, fallback_delay) do
    wakes
    |> Enum.filter(fn {_reason, delay} -> is_integer(delay) and delay > 0 end)
    |> Enum.min_by(fn {_reason, delay} -> delay end, fn -> {fallback_reason, fallback_delay} end)
  end
end
