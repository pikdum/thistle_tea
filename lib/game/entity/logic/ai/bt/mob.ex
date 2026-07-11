defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob do
  @moduledoc """
  The mob behavior tree: aggro checks, chasing and melee combat, spell-list
  casting, tethering back to spawn, and idle wandering or waypoint-route
  movement.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Aura, as: AuraBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen, as: RegenBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.Regen, as: RegenLogic
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @chase_tick_delay 1_000

  @approach_spread_scale 0.3
  @spread_detect_radius 2.0
  @spread_min_delay 2_500
  @spread_max_delay 3_500
  @spread_max_attempts 3
  @spread_min_offset 0.4
  @spread_max_offset 1.0
  @spread_min_gap 0.8
  @spread_gap 2.0
  @spread_gap_crowded 4.0
  @spread_crowd_threshold 5
  @back_movement_gap 1.0
  @deep_bounds_factor 0.5
  @distance_sqr_size_factor 1.0

  @default_detection_range 20.0
  @max_db_detection_range 45.0
  @max_level_aggro_bonus 25
  @min_aggro_radius 5.0
  @max_aggro_radius @max_db_detection_range + @max_level_aggro_bonus
  @aggro_check_delay 5_000
  @dead_idle_delay 1_000
  @blocked_retry_delay 1_000

  def max_aggro_radius, do: @max_aggro_radius

  def tree do
    BT.selector([
      AuraBT.tick_step(),
      RegenBT.tick_step(),
      BT.sequence([
        BT.condition(&tether_target_set?/2),
        BT.action(&wait_for_tether_arrival/2)
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
        BT.condition(&not_in_combat?/2),
        SpellBT.casting_sequence()
      ]),
      BT.action(&eventai_step/2),
      BT.sequence([
        BT.condition(&fleeing?/2),
        BT.action(&flee_step/2)
      ]),
      BT.sequence([
        BT.condition(&aggro_check_ready?/2),
        BT.condition(&not_in_combat?/2),
        BT.action(&try_aggro/2)
      ]),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.action(&select_victim/2),
        BT.action(&interrupt_idle_movement/2),
        BT.action(&set_running_true/2),
        BT.selector([
          BT.sequence([
            BT.condition(&target_dead?/2),
            BT.action(&eventai_target_dead/2),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&move_to_target/2)
          ]),
          BT.sequence([
            BT.condition(&should_tether?/2),
            BT.action(&eventai_evade/2),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&heal_to_full/2),
            BT.action(&move_to_target/2)
          ]),
          SpellBT.casting_sequence(),
          MobSpells.step(),
          BT.sequence([
            BT.condition(&target_valid_same_map?/2),
            MobSpells.hold_ranged_step()
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/2),
            BT.condition(&in_combat_range?/2),
            BT.action(&halt_at_contact/2),
            BT.action(&melee_attack/2),
            BT.action(&maybe_spread/2),
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

  defp eventai_step(%Mob{} = state, %Blackboard{} = blackboard) do
    {state, blackboard} = EventAI.tick(state, blackboard, Time.now())
    {:failure, state, blackboard}
  end

  defp eventai_step(state, %Blackboard{} = blackboard) do
    {:failure, state, blackboard}
  end

  defp eventai_target_dead(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard)
       when is_integer(target) and target > 0 do
    now = Time.now()
    {state, blackboard} = EventAI.on_kill(state, blackboard, target, now)
    {state, blackboard} = EventAI.on_leave_combat(state, blackboard, now)
    {:success, state, blackboard}
  end

  defp eventai_target_dead(state, %Blackboard{} = blackboard) do
    {:success, state, blackboard}
  end

  defp eventai_evade(%Mob{} = state, %Blackboard{} = blackboard) do
    now = Time.now()
    {state, blackboard} = EventAI.on_leave_combat(state, blackboard, now)
    {state, blackboard} = EventAI.on_evade(state, blackboard, now)
    {:success, state, blackboard}
  end

  @flee_min_distance 12.0
  @flee_max_distance 20.0
  @flee_repath_ms 1_500

  defp fleeing?(%Mob{}, %Blackboard{} = blackboard) do
    Blackboard.fleeing?(blackboard)
  end

  defp fleeing?(_state, _blackboard), do: false

  defp flee_step(%Mob{} = state, %Blackboard{} = blackboard) do
    flee_step(state, blackboard, Time.now())
  end

  def flee_step(%Mob{} = state, %Blackboard{flee_until: flee_until} = blackboard, now)
      when is_integer(flee_until) and is_integer(now) do
    cond do
      now >= flee_until or Core.dead?(state) ->
        {:failure, state, Blackboard.clear_flee(blackboard)}

      Movement.moving?(state, now) ->
        {BT.running(flee_wait_delay(state, blackboard, now), :flee), state, blackboard}

      true ->
        flee_move(state, blackboard, now)
    end
  end

  def flee_step(%Mob{} = state, %Blackboard{} = blackboard, _now) do
    {:failure, state, Blackboard.clear_flee(blackboard)}
  end

  defp flee_move(
         %Mob{movement_block: %MovementBlock{position: {mx, my, mz, _o}}} = state,
         %Blackboard{} = blackboard,
         now
       ) do
    from_guid = blackboard.flee_from || state.unit.target

    destination =
      case World.target_position(from_guid) do
        {map, tx, ty, _tz} when map == state.internal.map -> flee_destination({mx, my, mz}, {tx, ty})
        _ -> flee_destination({mx, my, mz}, nil)
      end

    state =
      state
      |> set_running(true)
      |> Movement.move_to(destination, [], now)

    {BT.running(flee_wait_delay(state, blackboard, now), :flee), state, blackboard}
  end

  defp flee_wait_delay(%Mob{} = state, %Blackboard{flee_until: flee_until}, now) do
    [Movement.remaining_move_duration(state, now), flee_until - now]
    |> soonest_delay(@flee_repath_ms)
    |> min(max(flee_until - now, 1))
  end

  defp flee_destination({mx, my, mz}, {tx, ty}) do
    away_angle = :math.atan2(my - ty, mx - tx)
    flee_destination_at({mx, my, mz}, away_angle + (:rand.uniform() - 0.5) * :math.pi() / 2.0)
  end

  defp flee_destination({mx, my, mz}, nil) do
    flee_destination_at({mx, my, mz}, :rand.uniform() * 2.0 * :math.pi())
  end

  defp flee_destination_at({mx, my, mz}, angle) do
    distance = @flee_min_distance + :rand.uniform() * (@flee_max_distance - @flee_min_distance)
    {mx + :math.cos(angle) * distance, my + :math.sin(angle) * distance, mz}
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

    case pick_aggro_target(state) do
      nil ->
        {:failure, state, blackboard}

      target_guid ->
        state = apply_aggro(state, target_guid, now)
        {state, blackboard} = EventAI.enter_combat(state, blackboard, target_guid, now)
        {:failure, state, blackboard}
    end
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
    radius = detection_range(state) + @max_level_aggro_bonus
    World.nearby_players(state, radius) ++ World.nearby_mobs(state, radius)
  end

  defp aggro_candidate?(%Mob{} = state, guid, distance) when is_integer(guid) and is_number(distance) do
    Hostility.valid_hostile_target?(state, guid) and distance <= aggro_radius(state, guid) and
      detectable_target?(state, guid, distance) and
      World.line_of_sight?(state, guid)
  end

  defp aggro_candidate?(_state, _guid, _distance), do: false

  defp detectable_target?(%Mob{unit: %Unit{level: level}}, guid, distance) do
    target = Metadata.query(guid, [:stealthed?, :stealth_skill, :undetectable_until])
    StealthDetection.detectable?(%{level: level}, target, distance, Time.now())
  end

  defp aggro_radius(%Mob{unit: %Unit{level: level}} = state, target_guid)
       when is_integer(level) and is_integer(target_guid) do
    aggro_radius_for(detection_range(state), level, target_level(target_guid), detect_range_modifier(state))
  end

  defp aggro_radius(%Mob{} = state, _target_guid), do: detection_range(state)

  def aggro_radius_for(detection_range, level, target_level, modifier \\ 0)

  def aggro_radius_for(detection_range, _level, _target_level, _modifier)
      when is_number(detection_range) and detection_range < 1 do
    0.0
  end

  def aggro_radius_for(detection_range, level, target_level, modifier)
      when is_number(detection_range) and is_integer(level) and is_integer(target_level) and is_integer(modifier) do
    level_diff = max(target_level - level, -@max_level_aggro_bonus)
    max(detection_range - level_diff + modifier, min(detection_range, @min_aggro_radius))
  end

  def detection_range(%Mob{internal: %Internal{creature: %Creature{detection_range: range}}}) when is_number(range) do
    range
  end

  def detection_range(%{detection_range: range}) when is_number(range), do: range

  def detection_range(_state), do: @default_detection_range

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

  defp apply_aggro(%Mob{internal: %Internal{} = internal} = state, target_guid, now) do
    state = %{state | internal: %{internal | in_combat: true, last_hostile_time: now}}

    state
    |> Threat.add(target_guid, 0)
    |> reselect_victim()
    |> CombatLogic.sync_combat_flag()
    |> Core.mark_broadcast_update()
  end

  def reselect_victim(%Mob{} = state) do
    case Threat.reselect(state) do
      {state, {:switch, new_guid}} ->
        state
        |> set_victim_state(new_guid)
        |> BT.reset_attack_started()

      {state, :keep} ->
        state
    end
  end

  defp select_victim(%Mob{} = state, %Blackboard{} = blackboard) do
    case Threat.reselect(state) do
      {state, {:switch, new_guid}} ->
        {state, blackboard} = maybe_on_kill(state, blackboard)
        state = set_victim_state(state, new_guid)
        {:success, state, Blackboard.clear_attack_started(blackboard)}

      {state, :keep} ->
        {:success, state, blackboard}
    end
  end

  defp maybe_on_kill(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard) do
    if target_dead?(state, blackboard) do
      EventAI.on_kill(state, blackboard, target, Time.now())
    else
      {state, blackboard}
    end
  end

  defp set_victim_state(%Mob{unit: %Unit{target: previous} = unit} = state, new_guid) do
    %{state | unit: %{unit | target: new_guid}}
    |> Event.enqueue(victim_change_events(previous, new_guid))
    |> Core.mark_broadcast_update()
  end

  defp victim_change_events(previous, new_guid) when is_integer(previous) and previous > 0 do
    [Event.attacker_lost(previous), Event.attacker_gained(new_guid)]
  end

  defp victim_change_events(_previous, new_guid) do
    [Event.attacker_gained(new_guid)]
  end

  defp set_running_true(%Mob{} = state, %Blackboard{} = blackboard) do
    {:success, set_running(state, true), blackboard}
  end

  defp interrupt_idle_movement(%Mob{} = state, %Blackboard{} = blackboard) do
    interrupt_idle_movement(state, blackboard, Time.now())
  end

  def interrupt_idle_movement(%Mob{} = state, %Blackboard{move_target: move_target} = blackboard, now)
      when is_tuple(move_target) and is_integer(now) do
    state =
      if Movement.moving?(state, now) do
        state
        |> Movement.halt(now)
        |> Event.enqueue(Event.movement_stopped())
      else
        state
      end

    blackboard = %{Blackboard.clear_waypoint(blackboard) | next_chase_at: 0}
    {:success, state, blackboard}
  end

  def interrupt_idle_movement(%Mob{} = state, %Blackboard{} = blackboard, _now) do
    {:success, state, blackboard}
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

  defp tether_target_set?(%Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}}, %Blackboard{
         move_target: {x, y, z}
       }) do
    true
  end

  defp tether_target_set?(_state, _blackboard), do: false

  defp wait_for_tether_arrival(%Mob{} = state, %Blackboard{} = blackboard) do
    now = Time.now()

    if Movement.moving?(state, now) do
      delay_ms = Movement.next_spatial_update_delay(state, now)
      {BT.running(delay_ms, :movement), state, blackboard}
    else
      {state, blackboard} = EventAI.on_reached_home(state, blackboard, now)
      {:success, state, Blackboard.clear_move_target(blackboard)}
    end
  end

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

  defp clear_combat(%Mob{} = state, %Blackboard{} = blackboard) do
    %Mob{unit: %Unit{target: target} = unit, internal: %Internal{} = internal} = state = Threat.wipe(state)
    unit = %{unit | target: 0, dynamic_flags: Bitwise.band(unit.dynamic_flags || 0, Bitwise.bnot(@dynamic_flag_tapped))}
    internal = %{internal | in_combat: false, loot: clear_tap(internal.loot)}

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.clear_attack()
      |> Blackboard.reset_spread()
      |> Blackboard.reset_spells()
      |> Blackboard.clear_flee()

    state = %{state | unit: unit, internal: internal}

    state =
      state
      |> SpellBT.clear_cast()
      |> CombatLogic.sync_combat_flag()
      |> Event.enqueue(clear_combat_events(state.object.guid, target))
      |> Core.mark_broadcast_update()

    {:success, state, blackboard}
  end

  def drop_threat(%Mob{} = state, source_guid) when is_integer(source_guid) do
    state = Threat.remove(state, source_guid)

    if Threat.entries(state) == [] do
      blackboard = Blackboard.from_any(state.internal.blackboard)
      {:success, state, blackboard} = clear_combat(state, blackboard)
      %{state | internal: %{state.internal | blackboard: blackboard}}
    else
      reselect_victim(state)
    end
  end

  def drop_threat(state, _source_guid), do: state

  defp clear_combat_events(source_guid, target) when is_integer(target) and target > 0 do
    [Event.attack_stop(source_guid, target), Event.attacker_lost(target), Event.tap_cleared()]
  end

  defp clear_combat_events(_source_guid, _target) do
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
    chase_delay = combat_chase_delay(state, blackboard, attack_delay, now)

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, chase_delay, now)

    {reason, delay_ms} =
      [
        {:attack, attack_delay},
        {:chase, chase_delay},
        {:spell, MobSpells.next_spell_delay(state, blackboard, now)},
        {:eventai, eventai_combat_delay(state, blackboard, now)},
        {:aura, aura_delay(state, now)},
        {:regen, regen_delay(state, blackboard, now)}
      ]
      |> soonest_wake(:chase, @chase_tick_delay)

    {BT.running(delay_ms, reason), state, blackboard}
  end

  defp melee_attack(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.melee_attack(state, blackboard)
  end

  defp halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard) do
    halt_at_contact(state, blackboard, Time.now())
  end

  def halt_at_contact(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
      when is_integer(target) and target > 0 and is_integer(now) do
    cond do
      not Movement.moving?(state, now) ->
        {:success, state, Blackboard.clear_spreading(blackboard)}

      Blackboard.spreading?(blackboard) ->
        {:success, state, blackboard}

      true ->
        maybe_halt_at_contact(state, blackboard, target, now)
    end
  end

  def halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, _now), do: {:success, state, blackboard}

  defp maybe_halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, target, now) do
    with {map, tx, ty, _tz} when map == state.internal.map <- World.target_position(target),
         true <- within_contact?(state, target, {tx, ty}) do
      state =
        state
        |> Movement.halt(now)
        |> face_position({tx, ty})
        |> Event.enqueue(Event.movement_stopped())

      {:success, state, blackboard}
    else
      _ -> {:success, state, blackboard}
    end
  end

  defp within_contact?(%Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state, target_guid, {tx, ty}) do
    planar_distance({mx, my, 0.0}, {tx, ty, 0.0}) <= contact_distance(state, target_guid)
  end

  defp contact_distance(%Mob{} = state, target_guid) do
    own_combat_reach(state) + target_combat_reach(target_guid)
  end

  defp face_position(%Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state, {tx, ty}) do
    set_orientation(state, :math.atan2(ty - my, tx - mx))
  end

  defp maybe_spread(%Mob{} = state, %Blackboard{} = blackboard) do
    maybe_spread(state, blackboard, Time.now())
  end

  def maybe_spread(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
      when is_integer(target) and target > 0 and is_integer(now) do
    cond do
      Movement.moving?(state, now) ->
        {:success, state, blackboard}

      not Blackboard.ready_for?(blackboard, :next_spread_at, now) ->
        {:success, state, blackboard}

      true ->
        blackboard = Blackboard.put_next_at(blackboard, :next_spread_at, spread_delay(), now)
        do_spread(state, blackboard, target, now)
    end
  end

  def maybe_spread(%Mob{} = state, %Blackboard{} = blackboard, _now), do: {:success, state, blackboard}

  defp do_spread(%Mob{} = state, %Blackboard{} = blackboard, target_guid, now) do
    if World.moving?(target_guid, now) do
      {:success, state, Blackboard.reset_spread(blackboard)}
    else
      back_or_spread(state, blackboard, target_guid, now)
    end
  end

  defp back_or_spread(%Mob{} = state, %Blackboard{} = blackboard, target_guid, now) do
    case back_movement(state, blackboard, target_guid, now) do
      {:moved, state, blackboard} ->
        {:success, state, blackboard}

      :skip ->
        if Blackboard.spread_attempts(blackboard) >= @spread_max_attempts do
          {:success, state, blackboard}
        else
          spread_from_neighbor(state, blackboard, target_guid, now)
        end
    end
  end

  defp back_movement(
         %Mob{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         %Blackboard{} = blackboard,
         target_guid,
         now
       ) do
    with {^map, tx, ty, tz} <- World.target_position(target_guid),
         true <- target_deep_in_bounds?(state, target_guid, {tx, ty}),
         {dx, dy, dz} <- back_movement_destination(state, target_guid, {mx, my}, {tx, ty, tz}) do
      state =
        state
        |> set_running(false)
        |> Movement.move_to({dx, dy, dz}, [face_target: target_guid], now)

      {:moved, state, Blackboard.mark_spreading(blackboard)}
    else
      _ -> :skip
    end
  end

  defp target_deep_in_bounds?(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         target_guid,
         {tx, ty}
       ) do
    bounds = @deep_bounds_factor * min(own_bounding_radius(state), target_bounding_radius(target_guid))
    planar_distance({mx, my, 0.0}, {tx, ty, 0.0}) < :math.sqrt(bounds + @distance_sqr_size_factor)
  end

  defp back_movement_destination(%Mob{} = state, target_guid, {mx, my}, {tx, ty, tz}) do
    angle = base_chase_angle({mx, my}, {tx, ty})
    center_distance = @back_movement_gap + own_bounding_radius(state) + target_bounding_radius(target_guid)

    if center_distance < melee_reach_to(state, target_guid) do
      {tx + :math.cos(angle) * center_distance, ty + :math.sin(angle) * center_distance, tz}
    end
  end

  defp spread_from_neighbor(%Mob{internal: %Internal{map: map}} = state, %Blackboard{} = blackboard, target_guid, now) do
    with {neighbor_guid, _distance} <- stacked_neighbor(state, target_guid),
         {^map, tx, ty, tz} <- World.target_position(target_guid),
         {_nmap, nx, ny, _nz} <- World.position(neighbor_guid),
         {dx, dy, dz} <- spread_destination(state, target_guid, {tx, ty, tz}, {nx, ny}) do
      state =
        state
        |> set_running(false)
        |> Movement.move_to({dx, dy, dz}, [face_target: target_guid], now)

      {:success, state, Blackboard.bump_spread(blackboard)}
    else
      _ -> {:success, state, blackboard}
    end
  end

  defp stacked_neighbor(%Mob{} = state, target_guid) do
    state
    |> World.nearby_mobs(@spread_detect_radius)
    |> Enum.filter(fn {other_guid, distance} ->
      other_guid != target_guid and distance < stack_threshold(state, other_guid)
    end)
    |> Enum.min_by(fn {_guid, distance} -> distance end, fn -> nil end)
  end

  defp stack_threshold(%Mob{} = state, other_guid) do
    bounds = min(max(own_bounding_radius(state), target_bounding_radius(other_guid)), 0.25)
    :math.sqrt(bounds + @distance_sqr_size_factor)
  end

  defp spread_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         target_guid,
         {tx, ty, tz},
         {nx, ny}
       ) do
    my_angle = :math.atan2(my - ty, mx - tx)
    his_angle = :math.atan2(ny - ty, nx - tx)
    new_angle = my_angle + spread_turn(my_angle, his_angle)
    center_distance = own_bounding_radius(state) + spread_gap(target_guid)

    if center_distance < melee_reach_to(state, target_guid) do
      {tx + :math.cos(new_angle) * center_distance, ty + :math.sin(new_angle) * center_distance, tz}
    end
  end

  defp spread_turn(my_angle, his_angle) do
    delta = @spread_min_offset + :rand.uniform() * (@spread_max_offset - @spread_min_offset)
    if angular_diff(his_angle, my_angle) > 0.0, do: -delta, else: delta
  end

  defp angular_diff(a, b) do
    :math.atan2(:math.sin(a - b), :math.cos(a - b))
  end

  defp spread_gap(target_guid) do
    max_gap = if attacker_count(target_guid) > @spread_crowd_threshold, do: @spread_gap_crowded, else: @spread_gap
    @spread_min_gap + :rand.uniform() * (max_gap - @spread_min_gap)
  end

  defp spread_delay do
    @spread_min_delay + :rand.uniform(@spread_max_delay - @spread_min_delay)
  end

  defp chase_repath_and_schedule(%Mob{} = state, %Blackboard{} = blackboard) do
    target = state.unit.target
    now = Time.now()

    case World.target_position(target) do
      {map, x, y, z} when map == state.internal.map ->
        {state, blackboard} = maybe_repath_chase(state, blackboard, {x, y, z}, target, now)
        delay_ms = chase_delay(state, target, {x, y}, now)
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
      destination = chase_destination(state, target_pos, target_guid, now)
      state = Movement.move_to(state, destination, [face_target: target_guid], now)
      {state, %{Blackboard.reset_spread(blackboard) | last_target_pos: target_pos}}
    else
      {state, blackboard}
    end
  end

  defp chase_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         {tx, ty, tz},
         target_guid,
         now
       ) do
    base_angle = base_chase_angle({mx, my}, {tx, ty})
    chase_distance = CombatLogic.chase_target_distance(melee_reach_to(state, target_guid))
    angle = base_angle + approach_angle_offset(state, target_guid, now)

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

  defp approach_angle_offset(%Mob{} = state, target_guid, now) do
    count = approach_spread_count(target_guid, now)

    if count > 0 do
      spread = :math.pi() / 2.0 - :math.pi() * :rand.uniform()
      spread * count / approach_size_factor(state, target_guid) * @approach_spread_scale
    else
      0.0
    end
  end

  defp approach_spread_count(target_guid, now) do
    if moving_player?(target_guid, now), do: 0, else: max(attacker_count(target_guid) - 1, 0)
  end

  defp moving_player?(target_guid, now) do
    Guid.type_id(target_guid) == :player and World.moving?(target_guid, now)
  end

  defp approach_size_factor(%Mob{} = state, target_guid) do
    factor = own_bounding_radius(state) + target_bounding_radius(target_guid)
    if factor < 0.1, do: Unit.default_bounding_radius(), else: factor
  end

  defp attacker_count(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:attacker_count]) do
      %{attacker_count: count} when is_number(count) and count > 0 -> count
      _ -> 0
    end
  end

  defp attacker_count(_target_guid), do: 0

  defp own_bounding_radius(%Mob{unit: %Unit{bounding_radius: radius}}) when is_number(radius) and radius > 0, do: radius
  defp own_bounding_radius(%Mob{}), do: Unit.default_bounding_radius()

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

  @melee_escape_min_threshold 0.5

  def melee_escape_distance(%Mob{} = state, target_guid, distance) when is_number(distance) do
    max(melee_reach_to(state, target_guid) - distance, @melee_escape_min_threshold)
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
    state = set_running(state, Blackboard.run_mode?(blackboard))

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
    state = set_running(state, Blackboard.run_mode?(blackboard))

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
      movement_delay = Movement.next_spatial_update_delay(state, now)
      {idle_reason, idle_delay} = idle_wake(state, blackboard, now)

      {reason, delay_ms} =
        [{:movement, movement_delay}, {idle_reason, idle_delay}]
        |> soonest_wake(:movement, movement_delay)

      {BT.running(delay_ms, reason), state, blackboard}
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

    {state, blackboard} = run_waypoint_scripts(state, blackboard)
    state = increment_waypoint(state)
    {:success, state, blackboard}
  end

  defp run_waypoint_scripts(%Mob{} = state, %Blackboard{} = blackboard) do
    case waypoint_destination(state) do
      %Waypoint{script_steps: [_ | _] = steps} -> Script.run(state, blackboard, steps, nil, Time.now())
      _ -> {state, blackboard}
    end
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
      {:eventai, EventAI.ooc_timer_delay(state, blackboard, now)},
      {:aura, aura_delay(state, now)},
      {:regen, regen_delay(state, blackboard, now)}
    ]
    |> soonest_wake(:aggro, @aggro_check_delay)
  end

  defp eventai_combat_delay(%Mob{} = state, %Blackboard{} = blackboard, now) do
    if EventAI.has_events?(state) do
      max(Blackboard.delay_until(blackboard, :next_eventai_at, now), 1)
    end
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

  defp chase_delay(%Mob{} = state, target_guid, {tx, ty}, now) do
    if Movement.moving?(state, now) do
      [
        Movement.remaining_move_duration(state, now),
        Movement.time_to_within(state, {tx, ty}, contact_distance(state, target_guid), now)
      ]
      |> soonest_delay(@chase_tick_delay)
      |> min(@chase_tick_delay)
    else
      @chase_tick_delay
    end
  end

  defp combat_chase_delay(%Mob{} = state, %Blackboard{} = blackboard, attack_delay, now) do
    cond do
      Movement.moving?(state, now) ->
        [Movement.next_spatial_update_delay(state, now), combat_contact_delay(state, blackboard, now)]
        |> soonest_delay(@chase_tick_delay)

      is_integer(attack_delay) and attack_delay > 0 ->
        attack_delay

      true ->
        @chase_tick_delay
    end
  end

  defp combat_contact_delay(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
       when is_integer(target) and target > 0 do
    if not Blackboard.spreading?(blackboard) do
      case World.target_position(target) do
        {map, tx, ty, _tz} when map == state.internal.map ->
          Movement.time_to_within(state, {tx, ty}, contact_distance(state, target), now)

        _ ->
          nil
      end
    end
  end

  defp combat_contact_delay(%Mob{}, %Blackboard{}, _now), do: nil

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
