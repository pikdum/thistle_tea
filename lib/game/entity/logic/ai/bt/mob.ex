defmodule ThistleTea.Game.Entity.Logic.AI.BT.Mob do
  @moduledoc """
  The mob behavior tree: aggro checks, chasing and melee combat, spell-list
  casting, tethering back to spawn, and idle wandering or waypoint-route
  movement.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Combat, as: CombatMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Navigation, as: NavigationMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: CombatBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Logic.TemporaryFaction
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

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
  @call_for_help_delay 1_000
  @call_for_help_spawn_distance 10.0

  def max_aggro_radius, do: @max_aggro_radius
  def combat_observation_radius, do: @spread_detect_radius

  def tree do
    BT.selector([
      BT.sequence([
        BT.condition(&tether_target_set?/2),
        BT.action(&wait_for_tether_arrival/3)
      ]),
      BT.sequence([
        BT.condition(&dead?/2),
        BT.action(&idle_dead/3)
      ]),
      BT.sequence([
        BT.condition(&stunned?/2),
        BT.action(&idle_stunned/3)
      ]),
      BT.sequence([
        BT.condition(&confused?/2),
        BT.action(&wait_until_confused_wander_ready/3),
        BT.action(&pick_confused_point/3),
        BT.action(&move_to_target_with_context/3),
        BT.action(&wait_for_arrival_with_context/3),
        BT.action(&set_next_confused_wait/3)
      ]),
      BT.sequence([
        BT.condition(&not_in_combat?/2),
        SpellBT.casting_sequence()
      ]),
      BT.action(&eventai_step/3),
      BT.sequence([
        BT.condition(&fleeing?/2),
        BT.action(&flee_step_with_context/3)
      ]),
      BT.sequence([
        BT.condition(&aggro_check_ready?/3),
        BT.condition(&not_in_combat?/2),
        BT.action(&try_aggro_with_context/3)
      ]),
      BT.sequence([
        BT.condition(&in_combat?/2),
        BT.action(&select_victim/3),
        BT.action(&interrupt_idle_movement/3),
        BT.action(&set_running_true/2),
        BT.action(&call_for_help_step/3),
        BT.selector([
          BT.sequence([
            BT.condition(&target_dead?/3),
            BT.action(&eventai_target_dead/3),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&move_to_target_with_context/3)
          ]),
          BT.sequence([
            BT.condition(&should_tether?/3),
            BT.action(&eventai_evade/3),
            BT.action(&set_tether_target/2),
            BT.action(&clear_combat/2),
            BT.action(&heal_to_full/2),
            BT.action(&move_to_target_with_context/3)
          ]),
          SpellBT.casting_sequence(),
          MobSpells.step(),
          BT.sequence([
            BT.condition(&target_valid_same_map?/3),
            MobSpells.hold_ranged_step()
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/3),
            BT.condition(&in_combat_range?/3),
            BT.action(&halt_at_contact/3),
            BT.action(&melee_attack/3),
            BT.action(&maybe_spread_with_context/3),
            BT.action(&combat_wait/3)
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/3),
            BT.condition(&chase_ready?/3),
            BT.action(&chase_repath_and_schedule/3)
          ]),
          BT.sequence([
            BT.condition(&target_valid_same_map?/3),
            BT.action(&wait_for_chase_tick/3)
          ]),
          BT.action(&clear_chase_and_idle/3)
        ])
      ]),
      BT.sequence([
        BT.condition(&scripted_home?/2),
        BT.action(&move_to_target_with_context/3),
        BT.action(&wait_for_scripted_home/3)
      ]),
      BT.sequence([
        BT.condition(&has_waypoints?/2),
        BT.action(&wait_until_waypoint_ready/3),
        BT.action(&pick_waypoint/3),
        BT.action(&move_to_target_with_context/3),
        BT.action(&wait_for_arrival_with_context/3),
        BT.action(&apply_waypoint/3),
        BT.action(&set_next_waypoint_wait/3)
      ]),
      BT.sequence([
        BT.condition(&can_wander?/2),
        BT.action(&wait_until_wander_ready/3),
        BT.action(&pick_wander_point/3),
        BT.action(&move_to_target_with_context/3),
        BT.action(&wait_for_arrival_with_context/3),
        BT.action(&set_next_wander_wait/3)
      ]),
      BT.action(&idle/3)
    ])
  end

  defp dead?(%Mob{} = state, _blackboard) do
    Core.dead?(state)
  end

  defp dead?(_state, _blackboard) do
    false
  end

  defp has_waypoints?(%Mob{}, %Blackboard{navigation: %NavigationMemory{movement_override: override}})
       when override in [:idle, :random], do: false

  defp has_waypoints?(%Mob{} = state, %Blackboard{} = blackboard),
    do: is_struct(waypoint_destination(state, blackboard), Waypoint)

  defp can_wander?(%Mob{}, %Blackboard{navigation: %NavigationMemory{movement_override: :random}}), do: true

  defp can_wander?(%Mob{}, %Blackboard{navigation: %NavigationMemory{movement_override: override}})
       when not is_nil(override), do: false

  defp can_wander?(%Mob{internal: %Internal{spawn: %Spawn{movement_type: 1}}}, _blackboard) do
    true
  end

  defp can_wander?(%Mob{}, _blackboard) do
    false
  end

  defp scripted_home?(%Mob{}, %Blackboard{navigation: %NavigationMemory{movement_override: :home}}), do: true
  defp scripted_home?(%Mob{}, %Blackboard{}), do: false

  defp wait_for_scripted_home(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    case wait_for_arrival(state, blackboard, context) do
      {:success, state, blackboard} ->
        {:success, state, Blackboard.clear_movement_override(blackboard)}

      result ->
        result
    end
  end

  @confused_wander_radius 4.0

  def confused_wander_radius, do: @confused_wander_radius

  defp confused?(%Mob{} = state, _blackboard) do
    AuraLogic.has_aura?(state, :mod_confuse) or AuraLogic.has_aura?(state, :mod_fear)
  end

  defp confused?(_state, _blackboard), do: false

  defp stunned?(%Mob{} = state, _blackboard) do
    AuraLogic.has_aura?(state, :mod_stun)
  end

  defp stunned?(_state, _blackboard), do: false

  defp idle_stunned(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    idle_stunned(state, blackboard, now)
  end

  defp idle_stunned(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    state = set_running(state, false)
    blackboard = Blackboard.clear_move_target(blackboard)
    {BT.running(@dead_idle_delay, :stunned), state, blackboard}
  end

  defp wait_until_confused_wander_ready(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    if Blackboard.ready_for?(blackboard, :next_confused_at, now) do
      {:success, state, blackboard}
    else
      delay_ms = Blackboard.delay_until(blackboard, :next_confused_at, now)
      {BT.running(delay_ms, :confused_wander), state, blackboard}
    end
  end

  defp pick_confused_point(
         %Mob{movement_block: %MovementBlock{position: {x, y, z, _o}}} = state,
         %Blackboard{} = blackboard,
         %Context{now: now} = context
       ) do
    state = set_running(state, false)
    blackboard = ensure_confused_anchor(state, blackboard, {x, y, z})

    if blackboard.navigation.target do
      {:success, state, blackboard}
    else
      {_key, anchor} = blackboard.navigation.confused_anchor

      case Navigation.wander_point(state, anchor, @confused_wander_radius, context) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_confused_at, confused_wait_delay(context), now)
          {:running, state, Blackboard.clear_move_target(blackboard)}

        {wx, wy, wz} ->
          navigation = %{blackboard.navigation | target: {wx, wy, wz}}
          {:success, state, %{blackboard | navigation: navigation}}
      end
    end
  end

  defp ensure_confused_anchor(%Mob{} = state, %Blackboard{} = blackboard, current_position) do
    key = AuraLogic.confuse_anchor_key(state)

    case blackboard.navigation.confused_anchor do
      {^key, _anchor} ->
        blackboard

      _ ->
        blackboard = Blackboard.clear_move_target(blackboard)
        %{blackboard | navigation: %{blackboard.navigation | confused_anchor: {key, current_position}}}
    end
  end

  defp set_next_confused_wait(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    blackboard = Blackboard.put_next_at(blackboard, :next_confused_at, confused_wait_delay(context), now)
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  defp confused_wait_delay(%Context{random: random}) do
    Random.integer(random, 1_000) + 500
  end

  defp eventai_step(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    {state, blackboard} = EventAI.tick(state, blackboard, now, context)
    {:failure, state, blackboard}
  end

  defp eventai_step(state, %Blackboard{} = blackboard, %Context{}) do
    {:failure, state, blackboard}
  end

  defp eventai_target_dead(
         %Mob{unit: %Unit{target: target}} = state,
         %Blackboard{} = blackboard,
         %Context{now: now} = context
       )
       when is_integer(target) and target > 0 do
    {state, blackboard} = EventAI.on_kill(state, blackboard, target, now, context)
    {state, blackboard} = EventAI.on_leave_combat(state, blackboard, now, context)
    {:success, state, blackboard}
  end

  defp eventai_target_dead(state, %Blackboard{} = blackboard, %Context{}) do
    {:success, state, blackboard}
  end

  defp eventai_evade(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    {state, blackboard} = EventAI.on_leave_combat(state, blackboard, now, context)
    {state, blackboard} = EventAI.on_evade(state, blackboard, now, context)
    {:success, state, blackboard}
  end

  @flee_min_distance 12.0
  @flee_max_distance 20.0
  @flee_repath_ms 1_500

  defp fleeing?(%Mob{} = state, %Blackboard{} = blackboard) do
    not AuraLogic.has_aura?(state, :prevent_fleeing) and Blackboard.fleeing?(blackboard)
  end

  defp fleeing?(_state, _blackboard), do: false

  defp flee_step_with_context(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    flee_step(state, blackboard, context)
  end

  defp flee_step(
         %Mob{} = state,
         %Blackboard{combat: %CombatMemory{flee_until: flee_until}} = blackboard,
         %Context{now: now} = context
       )
       when is_integer(flee_until) do
    cond do
      now >= flee_until or Core.dead?(state) ->
        {:failure, state, Blackboard.clear_flee(blackboard)}

      Movement.moving?(state, now) ->
        {BT.running(flee_wait_delay(state, blackboard, now), :flee), state, blackboard}

      true ->
        flee_move(state, blackboard, context)
    end
  end

  defp flee_step(%Mob{} = state, %Blackboard{} = blackboard, %Context{}) do
    {:failure, state, Blackboard.clear_flee(blackboard)}
  end

  defp flee_move(
         %Mob{movement_block: %MovementBlock{position: {mx, my, mz, _o}}} = state,
         %Blackboard{} = blackboard,
         %Context{now: now, perception: perception} = context
       ) do
    from_guid = blackboard.combat.flee_from || state.unit.target

    destination =
      case Perception.position(perception, from_guid) do
        {world, tx, ty, _tz} when world == state.internal.world ->
          flee_destination({mx, my, mz}, {tx, ty}, context)

        _ ->
          flee_destination({mx, my, mz}, nil, context)
      end

    state =
      state
      |> set_running(true)
      |> move_with_context(destination, [], context)

    {BT.running(flee_wait_delay(state, blackboard, now), :flee), state, blackboard}
  end

  defp flee_wait_delay(%Mob{} = state, %Blackboard{combat: %CombatMemory{flee_until: flee_until}}, now) do
    [Movement.remaining_move_duration(state, now), flee_until - now]
    |> soonest_delay(@flee_repath_ms)
    |> min(max(flee_until - now, 1))
  end

  defp flee_destination({mx, my, mz}, {tx, ty}, %Context{random: random}) do
    away_angle = :math.atan2(my - ty, mx - tx)
    flee_destination_at({mx, my, mz}, away_angle + (Random.float(random) - 0.5) * :math.pi() / 2.0, random)
  end

  defp flee_destination({mx, my, mz}, nil, %Context{random: random}) do
    flee_destination_at({mx, my, mz}, Random.float(random) * 2.0 * :math.pi(), random)
  end

  defp flee_destination_at({mx, my, mz}, angle, random) do
    distance = @flee_min_distance + Random.float(random) * (@flee_max_distance - @flee_min_distance)
    {mx + :math.cos(angle) * distance, my + :math.sin(angle) * distance, mz}
  end

  defp in_combat?(%Mob{} = state, %Blackboard{} = blackboard) do
    CombatBT.in_combat?(state, blackboard)
  end

  defp not_in_combat?(%Mob{} = state, %Blackboard{} = blackboard) do
    not in_combat?(state, blackboard)
  end

  def aggro_check_ready?(state, %Blackboard{} = blackboard, %Context{now: now}) do
    aggro_check_ready?(state, blackboard, now)
  end

  def aggro_check_ready?(_state, %Blackboard{} = blackboard, now) when is_integer(now) do
    Blackboard.ready_for?(blackboard, :next_aggro_at, now)
  end

  defp try_aggro_with_context(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    try_aggro(state, blackboard, context)
  end

  def try_aggro(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    try_aggro(state, blackboard, Context.new(now))
  end

  def try_aggro(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    blackboard = Blackboard.put_next_at(blackboard, :next_aggro_at, @aggro_check_delay, now)

    case pick_aggro_target(state, context) do
      nil ->
        {:failure, state, blackboard}

      target_guid ->
        state = apply_aggro(state, target_guid, now, context)
        {state, blackboard} = EventAI.enter_combat(state, blackboard, target_guid, now, context)
        {:failure, state, blackboard}
    end
  end

  defp pick_aggro_target(%Mob{} = state, %Context{perception: perception} = context) do
    if Hostility.can_initiate_attack?(perception_actor(state, perception)) do
      state
      |> nearby_aggro_candidates(context)
      |> Enum.filter(fn {guid, distance} -> aggro_candidate?(state, guid, distance, context) end)
      |> Enum.min_by(fn {_guid, distance} -> distance end, fn -> nil end)
      |> case do
        nil -> nil
        {guid, _distance} -> guid
      end
    end
  end

  defp nearby_aggro_candidates(%Mob{} = state, %Context{perception: perception}) do
    radius = detection_range(state) + @max_level_aggro_bonus
    Perception.nearby(perception, :players, radius) ++ Perception.nearby(perception, :mobs, radius)
  end

  defp aggro_candidate?(%Mob{} = state, guid, distance, %Context{perception: perception} = context)
       when is_integer(guid) and is_number(distance) do
    Hostility.valid_hostile_target?(
      perception_actor(state, perception),
      perception_target(perception, guid)
    ) and
      distance <= aggro_radius(state, guid, perception) and
      detectable_target?(state, guid, distance, context) and
      Perception.line_of_sight?(perception, guid)
  end

  defp aggro_candidate?(_state, _guid, _distance, %Context{}), do: false

  defp perception_target(perception, guid) do
    Perception.actor(perception, guid)
  end

  defp perception_actor(%Mob{object: %{guid: guid}}, perception) do
    Perception.actor(perception, guid)
  end

  defp detectable_target?(%Mob{unit: %Unit{level: level}}, guid, distance, %Context{now: now, perception: perception}) do
    StealthDetection.detectable?(%{level: level}, Perception.metadata(perception, guid), distance, now)
  end

  defp aggro_radius(%Mob{unit: %Unit{level: level}} = state, target_guid, perception)
       when is_integer(level) and is_integer(target_guid) do
    aggro_radius_for(detection_range(state), level, target_level(target_guid, perception), detect_range_modifier(state))
  end

  defp aggro_radius(%Mob{} = state, _target_guid, _perception), do: detection_range(state)

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

  defp target_level(guid, perception) when is_integer(guid) do
    case Perception.metadata(perception, guid) do
      %{level: level} when is_integer(level) -> level
      _ -> 1
    end
  end

  defp apply_aggro(%Mob{} = state, target_guid, now, %Context{} = context) do
    %Engagement.Result{entity: state} =
      Engagement.enter(state, target_guid, now, selection: victim_selection(state, context))

    state
    |> Core.mark_broadcast_update()
    |> maybe_enqueue_call_assistance(target_guid)
  end

  def maybe_enqueue_call_assistance(
        %Mob{internal: %Internal{pet: nil, totem: nil, creature: %Creature{call_for_help_range: range}}} = state,
        target_guid
      )
      when is_number(range) and range > 0 and is_integer(target_guid) and target_guid > 0 do
    Effects.enqueue(state, Effects.call_assistance(target_guid))
  end

  def maybe_enqueue_call_assistance(%Mob{} = state, _target_guid), do: state

  def call_for_help_step(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    call_for_help_step(state, blackboard, now)
  end

  def call_for_help_step(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_call_for_help_at, now) do
      blackboard = Blackboard.put_next_at(blackboard, :next_call_for_help_at, @call_for_help_delay, now)
      {:success, maybe_call_for_help(state), blackboard}
    else
      {:success, state, blackboard}
    end
  end

  defp maybe_call_for_help(
         %Mob{
           internal: %Internal{
             pet: nil,
             totem: nil,
             creature: %Creature{call_for_help_range: range},
             spawn: %Spawn{position: {sx, sy, sz}}
           },
           movement_block: %MovementBlock{position: {x, y, z, _o}},
           unit: %Unit{target: target}
         } = state
       )
       when is_number(range) and range > 0 and is_integer(target) and target > 0 do
    if Math.distance({sx, sy, sz}, {x, y, z}) > @call_for_help_spawn_distance do
      Effects.enqueue(state, Effects.call_for_help(target))
    else
      state
    end
  end

  defp maybe_call_for_help(%Mob{} = state), do: state

  defp select_victim(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    case Engagement.select(state, victim_selection(state, context)) do
      %Engagement.Result{
        entity: state,
        decision: {:switch, _new_guid},
        previous_victim: previous_victim
      } ->
        {state, blackboard} = maybe_on_kill(state, blackboard, previous_victim, context)
        {:success, state, Blackboard.clear_attack_started(blackboard)}

      %Engagement.Result{entity: state, decision: :keep} ->
        {:success, state, blackboard}

      %Engagement.Result{
        entity: state,
        decision: :none,
        previous_victim: previous_victim
      } ->
        {state, blackboard} = maybe_on_kill(state, blackboard, previous_victim, context)
        state = reset_after_combat(state, blackboard, context)
        {BT.running(0, :return_home), state, Blackboard.ensure(state.internal.blackboard)}
    end
  end

  defp maybe_on_kill(
         %Mob{} = state,
         %Blackboard{} = blackboard,
         target,
         %Context{now: now, perception: perception} = context
       ) do
    if target_dead_in_perception?(target, perception) do
      EventAI.on_kill(state, blackboard, target, now, context)
    else
      {state, blackboard}
    end
  end

  defp victim_selection(%Mob{} = state, %Context{perception: perception} = context) do
    [
      valid?: &valid_victim?(state, &1, context),
      in_melee?: &victim_in_melee?(state, &1, perception)
    ]
  end

  defp valid_victim?(%Mob{} = state, target_guid, %Context{perception: perception} = context) do
    Navigation.target_alive_same_map?(state, target_guid, context) and
      Hostility.valid_attack_target?(
        perception_actor(state, perception),
        Perception.actor(perception, target_guid)
      )
  end

  defp victim_in_melee?(%Mob{} = state, target_guid, perception) do
    case Perception.distance(perception, target_guid) do
      distance when is_number(distance) ->
        distance <= melee_reach_to(state, target_guid, perception)

      _ ->
        false
    end
  end

  defp set_running_true(%Mob{} = state, %Blackboard{} = blackboard) do
    {:success, set_running(state, true), blackboard}
  end

  def interrupt_idle_movement(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    interrupt_idle_movement(state, blackboard, now)
  end

  def interrupt_idle_movement(
        %Mob{} = state,
        %Blackboard{navigation: %NavigationMemory{move_target: move_target}} = blackboard,
        now
      )
      when is_tuple(move_target) and is_integer(now) do
    state =
      if Movement.moving?(state, now) do
        state
        |> Movement.halt(now)
        |> Effects.enqueue(Effects.movement_stopped())
      else
        state
      end

    blackboard = blackboard |> Blackboard.clear_waypoint() |> Blackboard.reset_deadline(:next_chase_at)
    {:success, state, blackboard}
  end

  def interrupt_idle_movement(%Mob{} = state, %Blackboard{} = blackboard, _now) do
    {:success, state, blackboard}
  end

  def should_tether?(%Mob{} = state, blackboard, %Context{now: now}) do
    should_tether?(state, blackboard, now)
  end

  def should_tether?(%Mob{} = state, _blackboard, now) when is_integer(now) do
    Core.should_tether?(state, now)
  end

  defp target_dead?(%Mob{unit: %Unit{target: target}}, _blackboard, %Context{perception: perception})
       when is_integer(target) and target > 0 do
    target_dead_in_perception?(target, perception)
  end

  defp target_dead?(_state, _blackboard, %Context{}), do: false

  defp target_dead_in_perception?(target, perception) when is_integer(target) and target > 0 do
    match?(%{alive?: false}, Perception.metadata(perception, target))
  end

  defp target_dead_in_perception?(_target, _perception), do: false

  defp tether_target_set?(%Mob{}, %Blackboard{navigation: %NavigationMemory{movement_override: :home}}), do: false

  defp tether_target_set?(%Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}}, %Blackboard{
         navigation: %NavigationMemory{move_target: {x, y, z}}
       }) do
    true
  end

  defp tether_target_set?(_state, _blackboard), do: false

  defp wait_for_tether_arrival(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    if Movement.moving?(state, now) do
      delay_ms = Movement.next_spatial_update_delay(state, now)
      {BT.running(delay_ms, :movement), state, blackboard}
    else
      state = state |> restore_spawn_orientation() |> TemporaryFaction.restore(:reach_home)
      {state, blackboard} = EventAI.on_reached_home(state, blackboard, now, context)
      {:success, state, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp restore_spawn_orientation(
         %Mob{
           movement_block: %MovementBlock{position: {x, y, z, current_orientation}} = movement_block,
           internal: %Internal{spawn: %Spawn{} = spawn}
         } = state
       ) do
    case home_orientation(spawn) do
      orientation when is_number(orientation) and orientation != current_orientation ->
        %{state | movement_block: %{movement_block | position: {x, y, z, orientation}}}
        |> Effects.enqueue(Effects.set_facing({:angle, orientation}))

      _orientation ->
        state
    end
  end

  defp restore_spawn_orientation(%Mob{} = state), do: state

  defp home_orientation(%Spawn{home_orientation: orientation}) when is_number(orientation), do: orientation

  defp home_orientation(%Spawn{movement_block: %MovementBlock{position: {_x, _y, _z, orientation}}}), do: orientation

  defp home_orientation(%Spawn{}), do: nil

  defp set_tether_target(
         %Mob{internal: %Internal{spawn: %Spawn{position: {x, y, z}}}} = state,
         %Blackboard{} = blackboard
       ) do
    navigation = %{blackboard.navigation | target: {x, y, z}}
    {:success, state, %{blackboard | navigation: navigation}}
  end

  defp set_tether_target(%Mob{} = state, %Blackboard{} = blackboard) do
    {:failure, state, blackboard}
  end

  defp clear_combat(%Mob{} = state, %Blackboard{} = blackboard) do
    %Engagement.Result{entity: state} = Engagement.leave(state, :evade, blackboard: blackboard)
    {:success, state, state.internal.blackboard}
  end

  def drop_threat(%Mob{} = state, source_guid) when is_integer(source_guid) do
    drop_threat(state, source_guid, Context.new(Time.now()))
  end

  def drop_threat(state, _source_guid), do: state

  def drop_threat(%Mob{} = state, source_guid, %Context{} = context) when is_integer(source_guid) do
    case Engagement.drop(state, source_guid) do
      %Engagement.Result{entity: state, reason: :untracked} -> state
      %Engagement.Result{entity: state, decision: :none} -> reset_after_combat(state, context)
      %Engagement.Result{entity: state} -> state
    end
  end

  def drop_threat(state, _source_guid, %Context{}), do: state

  defp reset_after_combat(%Mob{} = state, %Context{} = context) do
    reset_after_combat(state, Blackboard.ensure(state.internal.blackboard), context)
  end

  defp reset_after_combat(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    if Core.dead?(state), do: state, else: reset_living_after_combat(state, blackboard, context)
  end

  defp reset_living_after_combat(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    {state, blackboard} = EventAI.on_leave_combat(state, blackboard, now, context)
    {state, blackboard} = EventAI.on_evade(state, blackboard, now, context)

    case set_tether_target(state, blackboard) do
      {:success, state, blackboard} ->
        {:success, state, blackboard} = clear_combat(state, blackboard)
        {:success, state, blackboard} = heal_to_full(state, blackboard)
        {_status, state, blackboard} = move_to_target(state, blackboard, context)
        %{state | internal: %{state.internal | blackboard: blackboard}}

      {:failure, state, blackboard} ->
        {:success, state, blackboard} = clear_combat(state, blackboard)
        %{state | internal: %{state.internal | blackboard: blackboard}}
    end
  end

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

  defp target_valid_same_map?(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    CombatBT.target_valid_same_map?(state, blackboard, context)
  end

  defp in_combat_range?(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    CombatBT.in_combat_range?(state, blackboard, context)
  end

  def chase_ready?(state, %Blackboard{} = blackboard, %Context{now: now}) do
    chase_ready?(state, blackboard, now)
  end

  def chase_ready?(_state, %Blackboard{} = blackboard, now) when is_integer(now) do
    Blackboard.ready_for?(blackboard, :next_chase_at, now)
  end

  def combat_wait(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    combat_wait(state, blackboard, now, context)
  end

  def combat_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    combat_wait(state, blackboard, now, Context.new(now))
  end

  defp combat_wait(%Mob{} = state, %Blackboard{} = blackboard, now, %Context{} = context) do
    attack_delay = Blackboard.delay_until(blackboard, :next_attack_at, now)
    chase_delay = combat_chase_delay(state, blackboard, attack_delay, now, context)

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, chase_delay, now)

    {reason, delay_ms} =
      [
        {:attack, attack_delay},
        {:chase, chase_delay},
        {:spell, MobSpells.next_spell_delay(state, blackboard, now)},
        {:eventai, eventai_combat_delay(state, blackboard, now)}
      ]
      |> soonest_wake(:chase, @chase_tick_delay)

    {BT.running(delay_ms, reason), state, blackboard}
  end

  defp melee_attack(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    CombatBT.melee_attack_with_context(state, blackboard, context)
  end

  def halt_at_contact(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, %Context{
        now: now,
        perception: perception
      })
      when is_integer(target) and target > 0 do
    if Blackboard.spreading?(blackboard) and Movement.moving?(state, now) do
      {:success, state, blackboard}
    else
      maybe_halt_at_contact(state, Blackboard.clear_spreading(blackboard), target, now, perception)
    end
  end

  def halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, %Context{}), do: {:success, state, blackboard}

  def halt_at_contact(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
      when is_integer(target) and target > 0 and is_integer(now) do
    if Blackboard.spreading?(blackboard) and Movement.moving?(state, now) do
      {:success, state, blackboard}
    else
      maybe_halt_at_contact(state, Blackboard.clear_spreading(blackboard), target, now)
    end
  end

  def halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, _now), do: {:success, state, blackboard}

  defp maybe_halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, target, now) do
    with {world, tx, ty, _tz} when world == state.internal.world <- World.target_position(target),
         true <- within_contact?(state, target, {tx, ty}) do
      state =
        state
        |> maybe_halt(now)
        |> face_target(target, {tx, ty})

      {:success, state, blackboard}
    else
      _ -> {:success, state, blackboard}
    end
  end

  defp maybe_halt_at_contact(%Mob{} = state, %Blackboard{} = blackboard, target, now, perception) do
    with {world, tx, ty, _tz} when world == state.internal.world <- Perception.position(perception, target),
         true <- within_contact?(state, target, {tx, ty}, perception) do
      state =
        state
        |> maybe_halt(now)
        |> face_target(target, {tx, ty})

      {:success, state, blackboard}
    else
      _ -> {:success, state, blackboard}
    end
  end

  defp within_contact?(%Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state, target_guid, {tx, ty}) do
    planar_distance({mx, my, 0.0}, {tx, ty, 0.0}) <= contact_distance(state, target_guid)
  end

  defp within_contact?(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         target_guid,
         {tx, ty},
         perception
       ) do
    planar_distance({mx, my, 0.0}, {tx, ty, 0.0}) <= contact_distance(state, target_guid, perception)
  end

  defp contact_distance(%Mob{} = state, target_guid) do
    own_combat_reach(state) + target_combat_reach(target_guid)
  end

  defp contact_distance(%Mob{} = state, target_guid, perception) do
    own_combat_reach(state) + target_combat_reach(target_guid, perception)
  end

  defp maybe_halt(%Mob{} = state, now) do
    if Movement.moving?(state, now) do
      state
      |> Movement.halt(now)
      |> Effects.enqueue(Effects.movement_stopped())
    else
      state
    end
  end

  defp face_target(%Mob{movement_block: %MovementBlock{position: {_, _, _, previous}}} = state, target, position) do
    state = Movement.face_towards(state, position)
    {_, _, _, orientation} = state.movement_block.position

    if orientation == previous do
      state
    else
      Effects.enqueue(state, Effects.set_facing({:target, target}))
    end
  end

  defp maybe_spread_with_context(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    maybe_spread(state, blackboard, context)
  end

  def maybe_spread(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, %Context{now: now} = context)
      when is_integer(target) and target > 0 do
    cond do
      Movement.moving?(state, now) ->
        {:success, state, blackboard}

      not Blackboard.ready_for?(blackboard, :next_spread_at, now) ->
        {:success, state, blackboard}

      true ->
        blackboard = Blackboard.put_next_at(blackboard, :next_spread_at, spread_delay(context), now)
        do_spread(state, blackboard, target, context)
    end
  end

  def maybe_spread(%Mob{} = state, %Blackboard{} = blackboard, %Context{}), do: {:success, state, blackboard}

  defp do_spread(%Mob{} = state, %Blackboard{} = blackboard, target_guid, %Context{perception: perception} = context) do
    if Perception.moving?(perception, target_guid) do
      {:success, state, Blackboard.reset_spread(blackboard)}
    else
      back_or_spread(state, blackboard, target_guid, context)
    end
  end

  defp back_or_spread(%Mob{} = state, %Blackboard{} = blackboard, target_guid, %Context{} = context) do
    case back_movement(state, blackboard, target_guid, context) do
      {:moved, state, blackboard} ->
        {:success, state, blackboard}

      :skip ->
        if Blackboard.spread_attempts(blackboard) >= @spread_max_attempts do
          {:success, state, blackboard}
        else
          spread_from_neighbor(state, blackboard, target_guid, context)
        end
    end
  end

  defp back_movement(
         %Mob{internal: %Internal{world: world}, movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         %Blackboard{} = blackboard,
         target_guid,
         %Context{perception: perception} = context
       ) do
    with {^world, tx, ty, tz} <- Perception.position(perception, target_guid),
         true <- target_deep_in_bounds?(state, target_guid, {tx, ty}, perception),
         {dx, dy, dz} <- back_movement_destination(state, target_guid, {mx, my}, {tx, ty, tz}, context) do
      state =
        state
        |> set_running(false)
        |> move_with_context({dx, dy, dz}, [face_target: target_guid], context)

      {:moved, state, Blackboard.mark_spreading(blackboard)}
    else
      _ -> :skip
    end
  end

  defp target_deep_in_bounds?(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         target_guid,
         {tx, ty},
         perception
       ) do
    bounds = @deep_bounds_factor * min(own_bounding_radius(state), target_bounding_radius(target_guid, perception))
    planar_distance({mx, my, 0.0}, {tx, ty, 0.0}) < :math.sqrt(bounds + @distance_sqr_size_factor)
  end

  defp back_movement_destination(%Mob{} = state, target_guid, {mx, my}, {tx, ty, tz}, %Context{
         perception: perception,
         random: random
       }) do
    angle = base_chase_angle({mx, my}, {tx, ty}, random)
    center_distance = @back_movement_gap + own_bounding_radius(state) + target_bounding_radius(target_guid, perception)

    if center_distance < melee_reach_to(state, target_guid, perception) do
      {tx + :math.cos(angle) * center_distance, ty + :math.sin(angle) * center_distance, tz}
    end
  end

  defp spread_from_neighbor(
         %Mob{internal: %Internal{world: world}} = state,
         %Blackboard{} = blackboard,
         target_guid,
         %Context{perception: perception} = context
       ) do
    with {neighbor_guid, _distance} <- stacked_neighbor(state, target_guid, context),
         {^world, tx, ty, tz} <- Perception.position(perception, target_guid),
         {^world, nx, ny, _nz} <- Perception.position(perception, neighbor_guid),
         {dx, dy, dz} <- spread_destination(state, target_guid, {tx, ty, tz}, {nx, ny}, context) do
      state =
        state
        |> set_running(false)
        |> move_with_context({dx, dy, dz}, [face_target: target_guid], context)

      {:success, state, Blackboard.bump_spread(blackboard)}
    else
      _ -> {:success, state, blackboard}
    end
  end

  defp stacked_neighbor(%Mob{} = state, target_guid, %Context{perception: perception} = context) do
    perception
    |> Perception.nearby(:mobs, @spread_detect_radius)
    |> Enum.filter(fn {other_guid, distance} ->
      other_guid != target_guid and distance < stack_threshold(state, other_guid, context)
    end)
    |> Enum.min_by(fn {_guid, distance} -> distance end, fn -> nil end)
  end

  defp stack_threshold(%Mob{} = state, other_guid, %Context{perception: perception}) do
    bounds = min(max(own_bounding_radius(state), target_bounding_radius(other_guid, perception)), 0.25)
    :math.sqrt(bounds + @distance_sqr_size_factor)
  end

  defp spread_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         target_guid,
         {tx, ty, tz},
         {nx, ny},
         %Context{perception: perception, random: random}
       ) do
    my_angle = :math.atan2(my - ty, mx - tx)
    his_angle = :math.atan2(ny - ty, nx - tx)
    new_angle = my_angle + spread_turn(my_angle, his_angle, random)
    center_distance = own_bounding_radius(state) + spread_gap(target_guid, perception, random)

    if center_distance < melee_reach_to(state, target_guid, perception) do
      {tx + :math.cos(new_angle) * center_distance, ty + :math.sin(new_angle) * center_distance, tz}
    end
  end

  defp spread_turn(my_angle, his_angle, random) do
    delta = @spread_min_offset + Random.float(random) * (@spread_max_offset - @spread_min_offset)
    if angular_diff(his_angle, my_angle) > 0.0, do: -delta, else: delta
  end

  defp angular_diff(a, b) do
    :math.atan2(:math.sin(a - b), :math.cos(a - b))
  end

  defp spread_gap(target_guid, perception, random) do
    max_gap =
      if attacker_count(target_guid, perception) > @spread_crowd_threshold,
        do: @spread_gap_crowded,
        else: @spread_gap

    @spread_min_gap + Random.float(random) * (max_gap - @spread_min_gap)
  end

  defp spread_delay(%Context{random: random}) do
    @spread_min_delay + Random.integer(random, @spread_max_delay - @spread_min_delay)
  end

  defp chase_repath_and_schedule(
         %Mob{} = state,
         %Blackboard{} = blackboard,
         %Context{now: now, perception: perception} = context
       ) do
    target = state.unit.target

    case Perception.grounded_position(perception, target) do
      {world, x, y, z} when world == state.internal.world ->
        {state, blackboard} = maybe_repath_chase(state, blackboard, {x, y, z}, target, context)
        delay_ms = chase_delay(state, target, {x, y}, context)
        blackboard = Blackboard.put_next_at(blackboard, :next_chase_at, delay_ms, now)
        {BT.running(delay_ms, :chase), state, blackboard}

      _ ->
        clear_chase_and_idle(state, blackboard, context)
    end
  end

  def wait_for_chase_tick(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    wait_for_chase_tick(state, blackboard, now)
  end

  def wait_for_chase_tick(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    delay_ms = Blackboard.delay_until(blackboard, :next_chase_at, now)
    {BT.running(soonest_delay([delay_ms], @chase_tick_delay), :chase), state, blackboard}
  end

  def clear_chase_and_idle(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    delay_ms = idle_delay(context)

    blackboard =
      blackboard
      |> Blackboard.clear_chase()
      |> Blackboard.put_next_at(:next_chase_at, delay_ms, now)

    {BT.running(delay_ms, :idle), state, blackboard}
  end

  def clear_chase_and_idle(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    clear_chase_and_idle(state, blackboard, Context.new(now))
  end

  defp maybe_repath_chase(
         %Mob{} = state,
         %Blackboard{} = blackboard,
         target_pos,
         target_guid,
         %Context{now: now} = context
       ) do
    target_moved = target_moved_enough?(state, blackboard, target_pos, target_guid, context)
    should_repath = target_moved or not Movement.moving?(state, now)

    if should_repath do
      destination = chase_destination(state, target_pos, target_guid, context)

      state = Navigation.chase(state, target_guid, destination, context)

      blackboard = Blackboard.reset_spread(blackboard)
      navigation = %{blackboard.navigation | last_target_pos: target_pos}
      {state, %{blackboard | navigation: navigation}}
    else
      {state, blackboard}
    end
  end

  defp chase_destination(
         %Mob{movement_block: %MovementBlock{position: {mx, my, _mz, _o}}} = state,
         {tx, ty, tz},
         target_guid,
         %Context{now: now, perception: perception, random: random}
       ) do
    base_angle = base_chase_angle({mx, my}, {tx, ty}, random)
    chase_distance = CombatLogic.chase_target_distance(melee_reach_to(state, target_guid, perception))
    angle = base_angle + approach_angle_offset(state, target_guid, now, perception, random)

    {
      tx + :math.cos(angle) * chase_distance,
      ty + :math.sin(angle) * chase_distance,
      tz
    }
  end

  defp base_chase_angle({mx, my}, {tx, ty}, random) do
    dx = mx - tx
    dy = my - ty

    if abs(dx) < 1.0e-4 and abs(dy) < 1.0e-4 do
      Random.float(random) * :math.pi() * 2.0
    else
      :math.atan2(dy, dx)
    end
  end

  defp approach_angle_offset(%Mob{} = state, target_guid, now, perception, random) do
    count = approach_spread_count(target_guid, now, perception)

    if count > 0 do
      spread = :math.pi() / 2.0 - :math.pi() * Random.float(random)
      spread * count / approach_size_factor(state, target_guid, perception) * @approach_spread_scale
    else
      0.0
    end
  end

  defp approach_spread_count(target_guid, now, perception) do
    if moving_player?(target_guid, now, perception),
      do: 0,
      else: max(attacker_count(target_guid, perception) - 1, 0)
  end

  defp moving_player?(target_guid, _now, perception) do
    Guid.type_id(target_guid) == :player and Perception.moving?(perception, target_guid)
  end

  defp approach_size_factor(%Mob{} = state, target_guid, perception) do
    factor = own_bounding_radius(state) + target_bounding_radius(target_guid, perception)
    if factor < 0.1, do: Unit.default_bounding_radius(), else: factor
  end

  defp attacker_count(target_guid, perception) when is_integer(target_guid) do
    case Perception.metadata(perception, target_guid) do
      %{attacker_count: count} when is_number(count) and count > 0 -> count
      _ -> 0
    end
  end

  defp attacker_count(_target_guid, _perception), do: 0

  defp own_bounding_radius(%Mob{unit: %Unit{bounding_radius: radius}}) when is_number(radius) and radius > 0, do: radius
  defp own_bounding_radius(%Mob{}), do: Unit.default_bounding_radius()

  defp target_moved_enough?(
         %Mob{} = state,
         %Blackboard{navigation: %NavigationMemory{last_target_pos: {lx, ly, lz}}},
         {tx, ty, tz},
         target_guid,
         %Context{perception: perception}
       ) do
    threshold = chase_repath_distance(state, target_guid, perception)
    planar_distance({lx, ly, lz}, {tx, ty, tz}) > threshold
  end

  defp target_moved_enough?(%Mob{}, %Blackboard{}, {_x, _y, _z}, _target_guid, %Context{}), do: true

  defp planar_distance({x1, y1, _z1}, {x2, y2, _z2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  def chase_repath_distance(%Mob{} = state, target_guid) do
    CombatLogic.chase_rechase_distance(melee_reach_to(state, target_guid), target_bounding_radius(target_guid))
  end

  defp chase_repath_distance(%Mob{} = state, target_guid, perception) do
    CombatLogic.chase_rechase_distance(
      melee_reach_to(state, target_guid, perception),
      target_bounding_radius(target_guid, perception)
    )
  end

  @melee_escape_min_threshold 0.5

  def melee_escape_distance(%Mob{} = state, target_guid, distance) when is_number(distance) do
    max(melee_reach_to(state, target_guid) - distance, @melee_escape_min_threshold)
  end

  defp melee_reach_to(%Mob{} = state, target_guid) do
    CombatLogic.melee_reach(own_combat_reach(state), target_combat_reach(target_guid))
  end

  defp melee_reach_to(%Mob{} = state, target_guid, perception) do
    CombatLogic.melee_reach(own_combat_reach(state), target_combat_reach(target_guid, perception))
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

  defp target_combat_reach(target_guid, perception) when is_integer(target_guid) do
    case Perception.metadata(perception, target_guid) do
      %{combat_reach: combat_reach} when is_number(combat_reach) -> combat_reach
      _ -> Unit.default_combat_reach()
    end
  end

  defp target_combat_reach(_target_guid, _perception), do: Unit.default_combat_reach()

  defp target_bounding_radius(target_guid) when is_integer(target_guid) do
    case Metadata.query(target_guid, [:bounding_radius]) do
      %{bounding_radius: bounding_radius} when is_number(bounding_radius) -> bounding_radius
      _ -> Unit.default_bounding_radius()
    end
  end

  defp target_bounding_radius(_target_guid), do: Unit.default_bounding_radius()

  defp target_bounding_radius(target_guid, perception) when is_integer(target_guid) do
    case Perception.metadata(perception, target_guid) do
      %{bounding_radius: bounding_radius} when is_number(bounding_radius) -> bounding_radius
      _ -> Unit.default_bounding_radius()
    end
  end

  defp target_bounding_radius(_target_guid, _perception), do: Unit.default_bounding_radius()

  def wait_until_wander_ready(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    wait_until_wander_ready(state, blackboard, now)
  end

  def wait_until_wander_ready(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_wander_at, now) do
      {:success, state, blackboard}
    else
      {reason, delay_ms} = idle_wake(state, blackboard, :next_wander_at, now, :wander)
      {BT.running(delay_ms, reason), state, blackboard}
    end
  end

  def wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    wait_until_waypoint_ready(state, blackboard, now)
  end

  def wait_until_waypoint_ready(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    if Blackboard.ready_for?(blackboard, :next_waypoint_at, now) do
      {:success, state, blackboard}
    else
      {reason, delay_ms} = idle_wake(state, blackboard, :next_waypoint_at, now, :waypoint)
      {BT.running(delay_ms, reason), state, blackboard}
    end
  end

  defp pick_wander_point(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    state = set_running(state, Blackboard.run_mode?(blackboard))

    if blackboard.navigation.target do
      {:success, state, blackboard}
    else
      case Navigation.wander_point(
             state,
             wander_anchor(state, blackboard),
             wander_radius(state, blackboard),
             context
           ) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, idle_delay(context), now)
          blackboard = Blackboard.clear_move_target(blackboard)
          {reason, delay_ms} = idle_wake(state, blackboard, :next_wander_at, now, :wander)
          {BT.running(delay_ms, reason), state, blackboard}

        {x, y, z} ->
          navigation = %{blackboard.navigation | target: {x, y, z}}
          {:success, state, %{blackboard | navigation: navigation}}
      end
    end
  end

  defp wander_anchor(%Mob{}, %Blackboard{
         navigation: %NavigationMemory{movement_override: :random, wander_anchor: anchor}
       })
       when is_tuple(anchor), do: anchor

  defp wander_anchor(%Mob{internal: %Internal{spawn: %Spawn{position: position}}}, %Blackboard{}), do: position

  defp wander_radius(%Mob{}, %Blackboard{
         navigation: %NavigationMemory{movement_override: :random, wander_radius: radius}
       })
       when is_number(radius), do: radius

  defp wander_radius(%Mob{internal: %Internal{spawn: %Spawn{distance: distance}}}, %Blackboard{}), do: distance

  defp pick_waypoint(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    state = set_running(state, Blackboard.run_mode?(blackboard))

    if blackboard.navigation.target do
      {:success, state, blackboard}
    else
      case waypoint_destination(state, blackboard) do
        nil ->
          blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, idle_delay(context), now)
          blackboard = Blackboard.clear_waypoint(blackboard)
          {reason, delay_ms} = idle_wake(state, blackboard, :next_waypoint_at, now, :waypoint)
          {BT.running(delay_ms, reason), state, blackboard}

        %{position: {x, y, z, o}, wait_time: wait_time} ->
          navigation = %{
            blackboard.navigation
            | target: {x, y, z},
              orientation: o,
              wait_time: wait_time || 0
          }

          blackboard = %{blackboard | navigation: navigation}

          {:success, state, blackboard}
      end
    end
  end

  defp move_to_target_with_context(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    move_to_target(state, blackboard, context)
  end

  def move_to_target(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    case blackboard.navigation.target do
      {x, y, z} = target ->
        cond do
          Movement.blocked?(state) ->
            {BT.running(@blocked_retry_delay, :blocked), state, blackboard}

          blackboard.navigation.move_target == target ->
            {:success, state, blackboard}

          true ->
            state = move_with_context(state, {x, y, z}, [], context)
            navigation = %{blackboard.navigation | move_target: target}
            {:success, state, %{blackboard | navigation: navigation}}
        end

      _ ->
        {:failure, state, Blackboard.clear_move_target(blackboard)}
    end
  end

  defp wait_for_arrival_with_context(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    wait_for_arrival(state, blackboard, context)
  end

  def wait_for_arrival(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    wait_for_arrival(state, blackboard, Context.new(now))
  end

  def wait_for_arrival(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    {idle_reason, idle_delay} = idle_wake(state, blackboard, now)
    Navigation.wait_for_arrival(state, blackboard, context, [{idle_reason, idle_delay}])
  end

  defp apply_waypoint(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    state =
      case blackboard.navigation.orientation do
        o when is_number(o) -> set_orientation(state, o)
        _ -> state
      end

    {state, blackboard} = run_waypoint_scripts(state, blackboard, context)
    {state, blackboard} = increment_waypoint(state, blackboard)
    {:success, state, blackboard}
  end

  defp run_waypoint_scripts(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    case waypoint_destination(state, blackboard) do
      %Waypoint{script_steps: [_ | _] = steps} -> Script.run(state, blackboard, steps, nil, context)
      _ -> {state, blackboard}
    end
  end

  def set_next_waypoint_wait(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    set_next_waypoint_wait(state, blackboard, now)
  end

  def set_next_waypoint_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    wait_time = blackboard.navigation.wait_time || 0
    blackboard = Blackboard.put_next_at(blackboard, :next_waypoint_at, wait_time, now)
    {:success, state, Blackboard.clear_waypoint(blackboard)}
  end

  def set_next_wander_wait(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now} = context) do
    blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, wander_wait_delay(context), now)
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  def set_next_wander_wait(%Mob{} = state, %Blackboard{} = blackboard, now) when is_integer(now) do
    blackboard = Blackboard.put_next_at(blackboard, :next_wander_at, wander_wait_delay(Context.new(now)), now)
    {:success, state, Blackboard.clear_move_target(blackboard)}
  end

  defp idle(%Mob{} = state, %Blackboard{} = blackboard, %Context{now: now}) do
    state = set_running(state, false)
    {reason, delay_ms} = idle_wake(state, blackboard, now)
    {BT.running(delay_ms, reason), state, blackboard}
  end

  defp idle_dead(%Mob{} = state, %Blackboard{} = blackboard, %Context{}) do
    state = set_running(state, false)
    {BT.running(@dead_idle_delay, :dead), state, blackboard}
  end

  defp waypoint_destination(%Mob{} = state, %Blackboard{} = blackboard) do
    case waypoint_route(state, blackboard) do
      %WaypointRoute{} = route -> WaypointRoute.destination_waypoint(route)
      nil -> nil
    end
  end

  defp waypoint_route(%Mob{}, %Blackboard{
         navigation: %NavigationMemory{scripted_waypoint_route: %WaypointRoute{} = route}
       }) do
    route
  end

  defp waypoint_route(%Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route}}}, %Blackboard{}) do
    route
  end

  defp waypoint_route(%Mob{}, %Blackboard{}), do: nil

  defp increment_waypoint(
         %Mob{} = state,
         %Blackboard{navigation: %NavigationMemory{scripted_waypoint_route: %WaypointRoute{} = route} = navigation} =
           blackboard
       ) do
    navigation = %{navigation | scripted_waypoint_route: WaypointRoute.increment_waypoint(route)}
    {state, %{blackboard | navigation: navigation}}
  end

  defp increment_waypoint(
         %Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route} = spawn_state} = internal} =
           state,
         %Blackboard{} = blackboard
       ) do
    route = WaypointRoute.increment_waypoint(route)
    {%{state | internal: %{internal | spawn: %{spawn_state | waypoint_route: route}}}, blackboard}
  end

  defp increment_waypoint(%Mob{} = state, %Blackboard{} = blackboard), do: {state, blackboard}

  defp set_orientation(%Mob{movement_block: %MovementBlock{position: {x, y, z, _o}}} = state, o) do
    %{state | movement_block: %{state.movement_block | position: {x, y, z, o}}}
  end

  defp idle_delay(%Context{random: random}) do
    Random.integer(random, 4_000) + 2_000
  end

  defp wander_wait_delay(%Context{random: random}) do
    Random.integer(random, 6_000) + 4_000
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
      {:eventai, EventAI.ooc_timer_delay(state, blackboard, now)}
    ]
    |> soonest_wake(:aggro, @aggro_check_delay)
  end

  defp eventai_combat_delay(%Mob{} = state, %Blackboard{} = blackboard, now) do
    if EventAI.has_events?(state) do
      max(Blackboard.delay_until(blackboard, :next_eventai_at, now), 1)
    end
  end

  defp chase_delay(%Mob{} = state, target_guid, {tx, ty}, %Context{now: now, perception: perception}) do
    if Movement.moving?(state, now) do
      [
        Movement.remaining_move_duration(state, now),
        Movement.time_to_within(state, {tx, ty}, contact_distance(state, target_guid, perception), now)
      ]
      |> soonest_delay(@chase_tick_delay)
      |> min(@chase_tick_delay)
    else
      @chase_tick_delay
    end
  end

  defp combat_chase_delay(%Mob{} = state, %Blackboard{} = blackboard, attack_delay, now, %Context{} = context) do
    cond do
      Movement.moving?(state, now) ->
        [Movement.next_spatial_update_delay(state, now), combat_contact_delay(state, blackboard, context)]
        |> soonest_delay(@chase_tick_delay)

      is_integer(attack_delay) and attack_delay > 0 ->
        attack_delay

      true ->
        @chase_tick_delay
    end
  end

  defp combat_contact_delay(%Mob{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, %Context{
         now: now,
         perception: perception
       })
       when is_integer(target) and target > 0 do
    if not Blackboard.spreading?(blackboard) do
      case Perception.position(perception, target) do
        {world, tx, ty, _tz} when world == state.internal.world ->
          Movement.time_to_within(state, {tx, ty}, contact_distance(state, target, perception), now)

        _ ->
          nil
      end
    end
  end

  defp combat_contact_delay(%Mob{}, %Blackboard{}, %Context{}), do: nil

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

  defp move_with_context(%Mob{} = state, destination, opts, %Context{} = context) do
    Navigation.move_to(state, destination, opts, context)
  end
end
