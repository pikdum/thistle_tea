defmodule ThistleTea.Game.Core.AI.Script do
  @moduledoc """
  Interpreter for generic vmangos script-command steps, shared by EventAI
  actions and waypoint scripts. `run/5` executes the immediately-due steps and
  defers delayed steps back to the owning process through a `script_steps`
  event; `execute_steps/5` runs a batch whose delay already elapsed. Commands
  act on the pure entity state — enqueueing chat/emote/cast/summon/despawn
  events, swapping the unit display id for morphs, recursing into resolved
  generic scripts for start-script steps, and mutating the blackboard phase,
  gait, flee state, or waypoint hold (`hold_waypoints` holds the path until the
  summons spawned since are gone, or with `datalong2` 1 until
  `release_waypoints` lets it go) — steps with a failing condition are skipped,
  and unsupported commands are logged and skipped. The code-built
  `clear_auras` sheds the auras an evade would, for a script that ends a fight
  without one, and `stop_scripts` ends every script the creature is still
  running, as a C++ boss script's reset clears its timers; started scripts
  otherwise outlive an evade, as vmangos map scripts do. A `summon_object`
  step with `datalong3` 1 leaves the object unattached, as a C++ script's
  `SummonGameObject(..., false)` does, so players can open its lock.
  Initial target swaps move execution to the supplied owner
  before selection; final swaps move it to the selected owner. Conditions and
  commands then use the final source and target. Triggered casts use the
  trigger-spell pipeline; normal casts use the caster's
  mob or player casting machinery, and a game object casts every spell at once
  as vmangos objects do. Failed local target selection, conditions,
  and normal mob casts honor the abort flag. World-event commands and commands
  forwarded to another owner suspend their remaining steps until acknowledged.
  Continuations retain original due times and resume against current state.
  `execute_steps_with_status/5` exposes completion or suspension to EventAI so
  result-checked events retry after all their action groups finish.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.BT.Distancing
  alias ThistleTea.Game.Core.AI.BT.Flee
  alias ThistleTea.Game.Core.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Core.AI.BT.WaypointHold
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.CreatureSpellList
  alias ThistleTea.Game.Core.AI.Script.PetCommand
  alias ThistleTea.Game.Core.AI.Script.Run
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura, as: AuraCore
  alias ThistleTea.Game.Core.Combat.Assistance
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Combat.Sheath
  alias ThistleTea.Game.Core.Combat.Threat
  alias ThistleTea.Game.Core.Combat.ZoneCombat
  alias ThistleTea.Game.Core.Condition, as: ConditionEvaluator
  alias ThistleTea.Game.Core.Condition.EntityContext
  alias ThistleTea.Game.Core.Creature.CreatureEntry
  alias ThistleTea.Game.Core.Creature.CreatureGroup.Member
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Creature.CreatureReaction
  alias ThistleTea.Game.Core.Creature.ScriptEquipment
  alias ThistleTea.Game.Core.Creature.TemporaryFaction
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.GameObject.GameObjectActions
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Pet.Guardians
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.WorldRef

  require Logger

  @max_phase 31
  @hold_release_script 1
  @hold_expired_script 2
  @unattached_object 1
  @signal_hold 1
  @unit_flag_player_controlled 0x00000008
  @mana_power 0
  @scripted_event_commands [
    :set_server_variable,
    :start_map_event,
    :end_map_event,
    :add_map_event_target,
    :remove_map_event_target,
    :set_map_event_data,
    :send_map_event,
    :start_script_for_all,
    :start_script_on_zone,
    :edit_map_event
  ]
  @game_object_owner_commands [
    :activate_object,
    :set_game_object_state,
    :play_custom_animation,
    :reset_door_or_button,
    :remove_object
  ]
  @default_buddy_radius 30.0
  @summon_position_radius 40.0
  @occupied_distance 1.0
  @entry_target_types [
    :nearest_creature_with_entry,
    :random_creature_with_entry,
    :nearest_game_object_with_entry,
    :random_game_object_with_entry
  ]
  @null_source_target_types @entry_target_types ++
                              [
                                :creature_with_guid,
                                :creature_from_instance_data,
                                :game_object_with_guid,
                                :map_event_source,
                                :map_event_target,
                                :map_event_extra_target
                              ]

  def flee_duration_ms, do: Flee.duration_ms()

  def run(state, %Blackboard{} = blackboard, steps, target_guid, now) when is_list(steps) and is_integer(now) do
    run(state, blackboard, steps, target_guid, Context.new(now))
  end

  def run(state, %Blackboard{} = blackboard, steps, target_guid, %Context{} = context) when is_list(steps) do
    {state, blackboard, _status} = Run.start(state, blackboard, steps, target_guid, context, :scheduled)
    {state, blackboard}
  end

  def execute_steps(state, %Blackboard{} = blackboard, steps, target_guid, now)
      when is_list(steps) and is_integer(now) do
    execute_steps(state, blackboard, steps, target_guid, Context.new(now))
  end

  def execute_steps(state, %Blackboard{} = blackboard, steps, target_guid, %Context{} = context) when is_list(steps) do
    {state, blackboard, _status} = execute_steps_with_status(state, blackboard, steps, target_guid, context)
    {state, blackboard}
  end

  def execute_steps_with_status(
        state,
        %Blackboard{} = blackboard,
        steps,
        target_guid,
        %Context{} = context,
        completion \\ nil
      )
      when is_list(steps) do
    Run.start(state, blackboard, steps, target_guid, context, :direct, completion)
  end

  def execute_step(state, %Blackboard{} = blackboard, %ScriptStep{} = step, target_guid, %Context{} = context),
    do: dispatch(state, blackboard, step, target_guid, context)

  defp dispatch(
         %{object: %{guid: self_guid}} = state,
         blackboard,
         %ScriptStep{swap_initial?: true} = step,
         target_guid,
         %Context{} = context
       ) do
    cond do
      target_guid == self_guid ->
        dispatch(state, blackboard, %{step | swap_initial?: false}, self_guid, context)

      script_owner?(target_guid) ->
        forward(state, blackboard, %{step | swap_initial?: false, delay_ms: 0}, target_guid, self_guid)

      step.swap_final? and step.target_type in @null_source_target_types ->
        dispatch_final(state, blackboard, step, 0, self_guid, context)

      true ->
        failed(state, blackboard, step)
    end
  end

  defp dispatch(state, blackboard, %ScriptStep{swap_final?: true} = step, target_guid, %Context{} = context) do
    dispatch_final(state, blackboard, step, state.object.guid, target_guid, context)
  end

  defp dispatch(
         state,
         blackboard,
         %ScriptStep{command: command, target_type: target_type} = step,
         target_guid,
         %Context{} = context
       )
       when command in @game_object_owner_commands and
              target_type in [:nearest_game_object_with_entry, :game_object_with_guid] do
    dispatch_final(state, blackboard, step, state.object.guid, target_guid, context)
  end

  defp dispatch(state, blackboard, %ScriptStep{} = step, target_guid, %Context{now: now} = context) do
    selected = resolve_target(state, %{step | target_self?: false}, target_guid, context)
    target = if step.target_self?, do: state.object.guid, else: selected

    if (step.target_type == :provided or selected not in [nil, 0]) and
         condition_met?(state, step.condition, target, context) do
      case termination(state, step, target, context) do
        {:terminate, state} ->
          {state, blackboard, :terminated}

        :continue ->
          execute_command(state, blackboard, resolved_step(step), target, now, context)
      end
    else
      failed(state, blackboard, step)
    end
  end

  defp dispatch_final(state, blackboard, step, source_guid, target_guid, context) do
    owner = resolve_target(state, %{step | target_self?: false}, target_guid, context)
    target = if step.target_self?, do: owner, else: source_guid

    cond do
      owner == state.object.guid -> dispatch(state, blackboard, resolved_step(step), target, context)
      script_owner?(owner) -> forward(state, blackboard, resolved_step(step), owner, target)
      true -> failed(state, blackboard, step)
    end
  end

  defp failed(state, blackboard, %ScriptStep{abort_on_failure?: true}), do: {state, blackboard, :terminated}
  defp failed(state, blackboard, %ScriptStep{}), do: {state, blackboard, :continue}

  defp execute_command(
         %GameObject{} = state,
         blackboard,
         %ScriptStep{command: :cast_spell} = step,
         target_guid,
         _now,
         _
       ) do
    entry = CreatureSpell.from_script_step(step)

    if target_guid in [nil, 0] or entry.spell_id <= 0,
      do: failed(state, blackboard, step),
      else: {Effects.enqueue(state, Effects.scripted_cast(entry, target_guid)), blackboard, :continue}
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :cast_spell} = step, target_guid, _now, context) do
    entry = CreatureSpell.from_script_step(step)

    cond do
      target_guid in [nil, 0] or entry.spell_id <= 0 ->
        failed(state, blackboard, step)

      not MobSpells.flags_allow?(state, entry, target_guid, context) ->
        failed(state, blackboard, step)

      CreatureSpell.flag?(entry, :triggered) ->
        {trigger_cast(state, entry, target_guid, context), blackboard, :continue}

      is_struct(state, Character) ->
        {Effects.enqueue(state, Effects.scripted_cast(entry, target_guid)), blackboard, :continue}

      is_struct(state, Mob) ->
        cast_command(state, blackboard, entry, step, target_guid, context)

      true ->
        failed(state, blackboard, step)
    end
  end

  defp execute_command(state, blackboard, %ScriptStep{command: command}, _target_guid, _now, _context)
       when command in [:terminate_script, :terminate_condition] do
    {state, blackboard, :continue}
  end

  defp execute_command(state, blackboard, %ScriptStep{command: command} = step, target_guid, _now, _context)
       when command in @scripted_event_commands do
    effect = Effects.scripted_event_command(state.internal.world, state.object.guid, target_guid, step)
    {state, blackboard, {:await, effect}}
  end

  defp execute_command(
         %{unit: %Unit{}} = state,
         blackboard,
         %ScriptStep{command: :start_script_on_group} = step,
         target_guid,
         _now,
         %Context{random: random}
       ) do
    case choose_start_script(step, random) do
      nil ->
        failed(state, blackboard, step)

      script_id ->
        effect = %Effects.StartGroupScript{steps: Map.get(step.sub_scripts, script_id, []), target_guid: target_guid}
        {Effects.enqueue(state, effect), blackboard, :continue}
    end
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :start_script_on_group} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(
         %{unit: %Unit{}} = state,
         blackboard,
         %ScriptStep{command: :remove_guardians, datalong: entry},
         _target,
         now,
         _context
       )
       when is_integer(entry) and entry >= 0 do
    state = if entry == 0, do: Guardians.dismiss_all(state, now), else: Guardians.dismiss_entry(state, entry, now)
    {state, blackboard, :continue}
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :remove_guardians} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :creature_spells} = step,
         _target,
         _now,
         context
       ) do
    id = choose_option(ScriptStep.creature_spell_list_options(step), Random.integer(context.random, 100), 0) || 0
    list = if id == 0, do: %CreatureSpellList{id: 0}, else: Map.get(step.creature_spell_lists, id)

    case list do
      %CreatureSpellList{} -> {state, MobSpells.set_list(blackboard, list, context), :continue}
      nil -> {state, blackboard, :continue}
    end
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :creature_spells} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :set_react_state, datalong: reaction},
         _target,
         _now,
         _context
       )
       when reaction in 0..2 do
    mode = elem({:passive, :defensive, :aggressive}, reaction)
    {CreatureReaction.set(state, mode), blackboard, :continue}
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :set_react_state} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :set_command_state, datalong: command},
         target,
         _now,
         context
       ) do
    state = %{state | internal: %{state.internal | blackboard: blackboard}}
    state = PetCommand.apply(state, command, target, context)
    {state, state.internal.blackboard, :continue}
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :set_command_state} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :move_to} = step, target, _now, context) do
    case __MODULE__.MoveTo.apply(state, step, target, context) do
      {:ok, state} -> {state, blackboard, :continue}
      :error -> failed(state, blackboard, step)
    end
  end

  defp execute_command(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :zone_combat_pulse} = step,
         _target,
         _now,
         context
       ) do
    if Entity.dead?(state) do
      failed(state, blackboard, step)
    else
      state = %{state | internal: %{state.internal | blackboard: blackboard}}
      state = ZoneCombat.pulse(state, step.datalong != 0, context)
      {state, state.internal.blackboard, :continue}
    end
  end

  defp execute_command(state, blackboard, %ScriptStep{command: :zone_combat_pulse} = step, _target, _now, _context) do
    failed(state, blackboard, step)
  end

  defp execute_command(state, blackboard, step, target_guid, now, context) do
    {state, blackboard} = execute(state, blackboard, step, target_guid, now, context)
    {state, blackboard, :continue}
  end

  defp cast_command(state, blackboard, entry, step, target_guid, context) do
    case MobSpells.attempt_commanded_cast(state, blackboard, entry, target_guid, context) do
      {:ok, {state, blackboard}} -> {state, blackboard, :continue}
      {:error, _reason} -> failed(state, blackboard, step)
    end
  end

  defp condition_met?(_state, nil, _target_guid, _context), do: true

  defp condition_met?(state, condition, target_guid, context) do
    state
    |> EntityContext.build(context, target_guid)
    |> ConditionEvaluator.evaluate(condition)
    |> Kernel.==(:met)
  end

  defp resolved_step(%ScriptStep{} = step) do
    %{step | swap_initial?: false, swap_final?: false, target_self?: false, target_type: :provided, delay_ms: 0}
  end

  defp forward(state, blackboard, step, owner_guid, target_guid),
    do: {state, blackboard, {:await, Effects.forward_script_steps(owner_guid, [step], target_guid)}}

  defp script_owner?(guid) when is_integer(guid) and guid > 0,
    do: Guid.entity_type(guid) in [:mob, :player, :game_object]

  defp script_owner?(_guid), do: false

  defp termination(state, %ScriptStep{command: :terminate_script, datalong: 0}, _target_guid, %Context{}) do
    {:terminate, state}
  end

  defp termination(
         state,
         %ScriptStep{command: :terminate_script, datalong: entry, datalong2: radius, datalong3: option},
         _target_guid,
         %Context{perception: perception}
       )
       when entry > 0 do
    found? =
      perception
      |> Perception.nearby(:mobs, positive_radius(radius, @default_buddy_radius))
      |> Enum.any?(fn {guid, _distance} ->
        Perception.entry(perception, guid) == entry and alive_observation?(perception, guid)
      end)

    if (option == 0 and not found?) or (option == 1 and found?) do
      {:terminate, state}
    else
      :continue
    end
  end

  defp termination(
         %{object: %{guid: source_guid}} = state,
         %ScriptStep{
           command: :terminate_condition,
           datalong2: failed_quest_id,
           datalong3: flags,
           termination_condition: condition
         },
         target_guid,
         %Context{} = context
       ) do
    result =
      state
      |> EntityContext.build(context, target_guid)
      |> ConditionEvaluator.evaluate(condition)

    terminate? =
      case {result, flags &&& 0x1} do
        {:met, 0} -> true
        {:unmet, 1} -> true
        _unknown_or_not_selected -> false
      end

    if terminate? do
      state =
        case {failed_quest_id, script_player_guid(source_guid, target_guid)} do
          {quest_id, player_guid} when quest_id > 0 and is_integer(player_guid) ->
            Effects.enqueue(state, Effects.quest_fail(player_guid, quest_id, group?: true))

          _missing ->
            state
        end

      {:terminate, state}
    else
      :continue
    end
  end

  defp termination(_state, %ScriptStep{}, _target_guid, %Context{}), do: :continue

  defp occupied_position?(perception, {x, y, z, _orientation}) do
    perception
    |> Perception.nearby(:mobs, @summon_position_radius)
    |> Enum.any?(fn {guid, _distance} ->
      case Perception.position(perception, guid) do
        {_world, ox, oy, oz} ->
          alive_observation?(perception, guid) and Math.distance({x, y, z}, {ox, oy, oz}) < @occupied_distance

        _missing ->
          false
      end
    end)
  end

  defp alive_observation?(perception, guid) do
    case Perception.metadata(perception, guid) do
      %{alive?: alive?} -> alive?
      _metadata -> true
    end
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :update_entry} = step,
         _target,
         now,
         %Context{} = context
       ) do
    template = Random.weighted_choice(context.random, Map.get(context.creature_archetypes, step.datalong, []))
    updated = CreatureEntry.apply(state, template, now)

    blackboard =
      if updated.object.entry != state.object.entry and updated.internal.creature.spell_list_id not in [nil, 0],
        do: %{blackboard | spells: %{blackboard.spells | list: nil, timers: nil, next_list_at: 0}},
        else: blackboard

    {updated, blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :teleport_to} = step, _target_guid, now, %Context{}) do
    with true <- server_controlled_teleport_source?(state),
         {:ok, teleport} <- ScriptStep.teleport_to(step) do
      {state, transition} = Movement.teleport(state, teleport.position, now)

      effect =
        Effects.creature_teleported(
          state.internal.world,
          transition.from_position,
          transition.position,
          transition.movement_block,
          step.script_id,
          teleport.declared_map_id,
          teleport.options
        )

      {Effects.enqueue(state, effect), Blackboard.clear_move_target(blackboard)}
    else
      _unsupported -> {state, blackboard}
    end
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :hold_waypoints} = step, _target_guid, now, %Context{}) do
    steps = Map.get(step.sub_scripts, @hold_release_script, [])
    mode = if step.datalong2 == @signal_hold, do: :signal, else: :summons

    opts = [
      mode: mode,
      earlier_summons: state.internal.live_summons,
      expired_steps: Map.get(step.sub_scripts, @hold_expired_script)
    ]

    {state, WaypointHold.start(blackboard, now, step.datalong, steps, opts)}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :release_waypoints}, _target_guid, now, %Context{}) do
    {state, WaypointHold.release(blackboard, now)}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :start_waypoints} = step, _target_guid, now, %Context{
         waypoints: waypoints
       }) do
    cond do
      Entity.dead?(state) ->
        {state, blackboard}

      route = Waypoints.resolve(waypoints, state, step) ->
        {state, Blackboard.start_waypoints(blackboard, route, max(step.datalong3, 0), now)}

      true ->
        {state, blackboard}
    end
  end

  defp execute(
         %Mob{unit: %Unit{health: health}} = state,
         blackboard,
         %ScriptStep{command: :movement},
         _target,
         _now,
         %Context{}
       )
       when is_number(health) and health <= 0 do
    {state, blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :movement, datalong: 0}, _target, now, %Context{}) do
    {halt_scripted_movement(state, now), Blackboard.idle_movement(blackboard)}
  end

  defp execute(
         %Mob{internal: %{spawn: spawn}, movement_block: %{position: {x, y, z, _o}}} = state,
         blackboard,
         %ScriptStep{command: :movement, datalong: 1, position: {radius, _, _, _}} = step,
         _target,
         now,
         %Context{}
       )
       when not is_nil(spawn) do
    anchor = if step.datalong2 == 0, do: spawn.position || {x, y, z}, else: {x, y, z}
    state = halt_scripted_movement(state, now)
    {state, Blackboard.start_wander(blackboard, anchor, max(radius, 0))}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :movement, datalong: 2} = step, _target, now, %Context{
         waypoints: waypoints
       }) do
    waypoint_step = %{
      step
      | command: :start_waypoints,
        datalong: 0,
        datalong2: step.datalong3,
        datalong3: 0,
        datalong4: step.datalong2,
        dataint: 0,
        dataint2: 0
    }

    case Waypoints.resolve(waypoints, state, waypoint_step) do
      nil -> {state, blackboard}
      route -> {halt_scripted_movement(state, now), Blackboard.start_waypoints(blackboard, route, 0, now)}
    end
  end

  defp execute(
         %Mob{internal: %{spawn: %{position: {x, y, z}}}} = state,
         blackboard,
         %ScriptStep{command: :movement, datalong: 7},
         _target,
         now,
         %Context{}
       ) do
    {halt_scripted_movement(state, now), Blackboard.start_home(blackboard, {x, y, z})}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :movement, datalong: 10} = step,
         target,
         now,
         %Context{}
       ) do
    from_guid = if step.datalong2 == 0, do: target, else: state.unit.target
    duration_ms = if step.datalong3 > 0, do: step.datalong3, else: Flee.duration_ms()

    if is_integer(from_guid) and from_guid > 0 and from_guid != state.object.guid,
      do: Flee.run_from(state, blackboard, from_guid, duration_ms, now),
      else: {state, blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :movement, datalong: 19} = step, target, _now, context) do
    if step.datalong3 == 0 or (Entity.mana_pct(state) || 0) >= step.datalong3 do
      Distancing.start(state, blackboard, resolve_target(state, step, target, context), elem(step.position, 0), context)
    else
      {state, blackboard}
    end
  end

  defp execute(
         %Mob{object: %{guid: guid}} = state,
         blackboard,
         %ScriptStep{command: :movement, datalong: 15} = step,
         leader,
         now,
         %Context{random: random}
       )
       when is_integer(leader) and leader > 0 and leader != guid do
    {distance, angle} =
      case step.position do
        {distance, _y, _z, angle} -> {max(distance, 0.0), angle}
        nil -> {0.0, 0.0}
      end

    angle = if angle < 0, do: Random.float(random) * 2 * :math.pi(), else: angle
    {halt_scripted_movement(state, now), Blackboard.start_follow(blackboard, leader, distance, angle)}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :movement}, _target, _now, %Context{}) do
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :interrupt_casts} = step, _target, now, %Context{}) do
    {interrupt_casts(state, step.datalong2, now), blackboard}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :set_equipment, datalong: reset_default},
         _target,
         _now,
         %Context{}
       )
       when reset_default != 0 do
    state = ScriptEquipment.reset(state)
    {Entity.mark_broadcast_update(state), blackboard}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :set_equipment, datalong: 0, equipment_items: [_, _, _] = items},
         _target,
         _now,
         %Context{}
       ) do
    state = %{state | unit: ScriptEquipment.apply(state.unit, items)}
    {Entity.mark_broadcast_update(state), blackboard}
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :meeting_stone, datalong: area},
         target_guid,
         _now,
         %Context{}
       )
       when is_integer(area) and area > 0 do
    case script_player_guid(source_guid, target_guid) do
      nil ->
        {state, blackboard}

      player_guid ->
        effect = %Effects.MeetingStoneQueue{player_guid: player_guid, area: area, world: state.internal.world}
        {Effects.enqueue(state, effect), blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :quest_explored, datalong: quest_id} = step,
         target_guid,
         _now,
         %Context{}
       )
       when is_integer(quest_id) and quest_id > 0 do
    case script_player_guid(source_guid, target_guid) do
      nil ->
        {state, blackboard}

      player_guid ->
        opts = [
          group?: step.datalong3 != 0,
          distance: max(step.datalong2, 0),
          world_object_guid: script_world_object_guid(source_guid, target_guid)
        ]

        {Effects.enqueue(state, Effects.quest_event_credit(player_guid, quest_id, opts)), blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :kill_credit, datalong: creature_entry} = step,
         target_guid,
         _now,
         %Context{}
       )
       when is_integer(creature_entry) and creature_entry > 0 do
    case script_player_guid(source_guid, target_guid) do
      nil ->
        {state, blackboard}

      player_guid ->
        event = Effects.quest_kill_credit(player_guid, creature_entry, group?: step.datalong2 != 0)
        {Effects.enqueue(state, event), blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid, entry: source_entry}} = state,
         blackboard,
         %ScriptStep{command: :cast_credit, datalong: spell_id},
         target_guid,
         _now,
         %Context{}
       )
       when is_integer(spell_id) and spell_id > 0 do
    case script_player_guid(source_guid, target_guid) do
      player_guid when player_guid in [nil, source_guid] ->
        {state, blackboard}

      player_guid ->
        effect =
          Effects.quest_cast_credit([source_guid], spell_id, player_guid: player_guid, target_entry: source_entry)

        {Effects.enqueue(state, effect), blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :fail_quest, datalong: quest_id},
         target_guid,
         _now,
         %Context{}
       )
       when is_integer(quest_id) and quest_id > 0 do
    case script_player_guid(source_guid, target_guid) do
      nil -> {state, blackboard}
      player_guid -> {Effects.enqueue(state, Effects.quest_fail(player_guid, quest_id, group?: true)), blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :quest_credit},
         target_guid,
         _now,
         %Context{}
       ) do
    player_guid = script_player_guid(source_guid, target_guid)
    world_object_guid = script_world_object_guid(source_guid, target_guid)

    if is_integer(player_guid) and is_integer(world_object_guid) do
      {Effects.enqueue(state, Effects.quest_interaction_credit(player_guid, world_object_guid)), blackboard}
    else
      {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :talk} = step,
         target_guid,
         _now,
         %Context{random: random} = context
       ) do
    case pick_talk_text(step, random) do
      nil -> {state, blackboard}
      text -> {talk(state, text, resolve_target(state, step, target_guid, context)), blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :emote} = step, _target_guid, _now, %Context{random: random}) do
    case ScriptStep.emote_ids(step) do
      [] -> {state, blackboard}
      emote_ids -> {Effects.enqueue(state, Effects.emote(Random.choice(random, emote_ids))), blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :start_waypoints}, _target_guid, _now, %Context{}) do
    {state, blackboard}
  end

  defp execute(
         %Mob{internal: %{spawn: spawn} = internal} = state,
         blackboard,
         %ScriptStep{command: :set_default_movement} = step,
         _target_guid,
         _now,
         %Context{waypoints: waypoints}
       )
       when not is_nil(spawn) do
    movement_type = step.datalong

    route =
      if movement_type == 2 do
        default_step = %{
          step
          | command: :start_waypoints,
            datalong: 0,
            datalong2: 0,
            datalong4: 1,
            dataint: 0,
            dataint2: 0
        }

        Waypoints.resolve(waypoints, state, default_step)
      end

    spawn = %{
      spawn
      | movement_type: movement_type,
        distance: if(movement_type == 1, do: step.datalong3, else: spawn.distance),
        waypoint_route: route
    }

    blackboard = Blackboard.clear_movement_override(blackboard)
    {%{state | internal: %{internal | spawn: spawn}}, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_default_movement}, _target_guid, _now, %Context{}) do
    {state, blackboard}
  end

  defp execute(
         %Mob{internal: %{spawn: spawn} = internal} = state,
         blackboard,
         %ScriptStep{command: :set_home_position} = step,
         _target_guid,
         _now,
         %Context{}
       )
       when not is_nil(spawn) do
    case home_position(state, step) do
      {x, y, z, orientation} ->
        spawn = %{spawn | position: {x, y, z}, home_orientation: orientation}
        {%{state | internal: %{internal | spawn: spawn}}, blackboard}

      nil ->
        {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :summon_creature, count: count} = step,
         target_guid,
         now,
         %Context{} = context
       )
       when count != 1 do
    state
    |> summon_count(count, context)
    |> then(&Enum.to_list(1..&1//1))
    |> Enum.reduce({state, blackboard}, fn _index, {state, blackboard} ->
      execute(state, blackboard, %{step | count: 1}, target_guid, now, context)
    end)
  end

  defp execute(
         %{internal: %{world: world}} = state,
         blackboard,
         %ScriptStep{command: :summon_creature, at_target?: true} = step,
         target_guid,
         now,
         %Context{perception: perception} = context
       ) do
    {_x, _y, _z, orientation} = state.movement_block.position

    case Perception.position(perception, resolve_target(state, step, target_guid, context)) do
      {^world, x, y, z} ->
        execute(
          state,
          blackboard,
          %{step | at_target?: false, position: {x, y, z, orientation}},
          target_guid,
          now,
          context
        )

      _missing ->
        {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :summon_creature, positions: [_ | _] = positions} = step,
         target_guid,
         now,
         %Context{perception: perception, random: random} = context
       ) do
    case Enum.reject(positions, &occupied_position?(perception, &1)) do
      [] ->
        {state, blackboard}

      vacant ->
        execute(
          state,
          blackboard,
          %{step | positions: [], position: Random.choice(random, vacant)},
          target_guid,
          now,
          context
        )
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :summon_creature} = step,
         target_guid,
         _now,
         %Context{} = context
       ) do
    summon =
      step
      |> ScriptStep.summon()
      |> resolve_summon_position(state)
      |> Map.put(:attack_guid, resolve_summon_attack(state, step, target_guid, context))

    steps = Map.get(step.sub_scripts, summon.script_id, [])
    {Effects.enqueue(state, Effects.summon_creature(summon, steps, target_guid)), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :attack_start} = step, target_guid, _now, %Context{} = context) do
    case resolve_target(state, step, target_guid, context) do
      guid when is_integer(guid) and guid > 0 and guid != state.object.guid ->
        {Effects.enqueue(state, Effects.attack_start(guid)), blackboard}

      _ ->
        {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :send_taxi_path, datalong: path_id} = step,
         target_guid,
         _now,
         %Context{} = context
       )
       when is_integer(path_id) and path_id > 0 do
    case resolve_target(state, step, target_guid, context) do
      guid when is_integer(guid) ->
        if Guid.entity_type(guid) == :player do
          {Effects.enqueue(state, Effects.send_taxi_path(guid, path_id)), blackboard}
        else
          {state, blackboard}
        end

      _ ->
        {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :start_script} = step,
         target_guid,
         _now,
         %Context{random: random} = context
       ) do
    case choose_start_script(step, random) do
      nil -> {state, blackboard}
      script_id -> run(state, blackboard, Map.get(step.sub_scripts, script_id, []), target_guid, context)
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :turn_to, datalong: 0} = step,
         target_guid,
         _now,
         %Context{} = context
       ) do
    case resolve_target(state, step, target_guid, context) do
      guid when is_integer(guid) and guid > 0 and guid != state.object.guid ->
        state = face_observed_target(state, guid, context.perception)
        {Effects.enqueue(state, Effects.set_facing({:target, guid})), blackboard}

      _ ->
        {state, blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_phase_random} = step, _target_guid, _now, %Context{
         random: random
       }) do
    candidates = [step.datalong, step.datalong2] ++ Enum.take_while([step.datalong3, step.datalong4], &(&1 > 0))
    {state, put_phase(blackboard, Random.choice(random, candidates))}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_phase_range} = step, _target_guid, _now, %Context{
         random: random
       })
       when step.datalong2 >= step.datalong do
    {state, put_phase(blackboard, Random.between(random, step.datalong, step.datalong2))}
  end

  defp execute(
         %GameObject{} = state,
         blackboard,
         %ScriptStep{command: :activate_object},
         target_guid,
         _now,
         %Context{} = context
       ) do
    case resolve_target(state, %ScriptStep{target_type: :provided}, target_guid, context) do
      user_guid when is_integer(user_guid) ->
        {Effects.enqueue(state, Effects.activate_game_object(user_guid)), blackboard}

      _missing_user ->
        {state, blackboard}
    end
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: command, datalong2: reset_delay_seconds, game_object_spawn: %GameObject{} = blueprint},
         _target_guid,
         _now,
         %Context{}
       )
       when command in [:open_door, :close_door] do
    action = if command == :open_door, do: :open, else: :close
    reset_delay_ms = max(reset_delay_seconds, 3) * 1_000
    effect = Effects.operate_game_object(action, reset_delay_ms, blueprint: blueprint)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(
         %GameObject{} = state,
         blackboard,
         %ScriptStep{command: command, datalong2: reset_delay_seconds},
         _target_guid,
         _now,
         %Context{}
       )
       when command in [:open_door, :close_door] do
    action = if command == :open_door, do: :open, else: :close
    reset_delay_ms = max(reset_delay_seconds, 3) * 1_000
    {Effects.enqueue(state, Effects.operate_game_object(action, reset_delay_ms)), blackboard}
  end

  defp execute(
         %GameObject{} = state,
         blackboard,
         %ScriptStep{command: :reset_door_or_button},
         _target_guid,
         _now,
         %Context{}
       ) do
    {Effects.enqueue(state, Effects.operate_game_object(:reset, 0)), blackboard}
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{
           command: :respawn_game_object,
           game_object_spawn: %GameObject{} = blueprint,
           datalong2: duration_seconds
         },
         _target_guid,
         _now,
         %Context{}
       ) do
    duration_ms = max(duration_seconds, 5) * 1_000
    {Effects.enqueue(state, Effects.respawn_game_object(blueprint, duration_ms)), blackboard}
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{
           command: :despawn_game_object,
           game_object_spawn: %GameObject{} = blueprint,
           datalong2: respawn_delay_seconds
         },
         _target_guid,
         _now,
         %Context{}
       ) do
    respawn_delay_ms = positive_seconds(respawn_delay_seconds)
    {Effects.enqueue(state, Effects.despawn_game_object(blueprint, respawn_delay_ms)), blackboard}
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :load_game_object_spawn, game_object_spawn: %GameObject{} = blueprint},
         _target_guid,
         _now,
         %Context{}
       ) do
    {Effects.enqueue(state, Effects.load_game_object_spawn(blueprint)), blackboard}
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :load_creature_spawn, datalong: db_guid},
         _target_guid,
         _now,
         %Context{}
       )
       when is_integer(db_guid) and db_guid > 0 do
    {Effects.enqueue(state, Effects.load_creature_spawn(db_guid)), blackboard}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :modify_threat, datalong: 8, position: {percent, _y, _z, _o}},
         _target_guid,
         _now,
         %Context{}
       ) do
    {Threat.modify_all_percent(state, percent), blackboard}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :modify_threat} = step,
         target_guid,
         _now,
         %Context{} = context
       ) do
    target_step = %{step | target_type: ScriptStep.decode_target_type(step.datalong), target_self?: false}

    case resolve_target(state, target_step, target_guid, context) do
      guid when is_integer(guid) -> {Threat.modify_percent(state, guid, elem(step.position, 0)), blackboard}
      _missing -> {state, blackboard}
    end
  end

  defp execute(
         %{object: %{guid: source_guid}} = state,
         blackboard,
         %ScriptStep{command: :send_script_event} = step,
         target_guid,
         _now,
         %Context{} = context
       ) do
    invoker_guid = resolve_target(state, step, target_guid, context)
    effect = Effects.send_script_event(source_guid, invoker_guid, step.datalong, step.datalong2)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(
         %{internal: %{world: world}} = state,
         blackboard,
         %ScriptStep{command: :set_instance_data} = step,
         _target_guid,
         _now,
         %Context{}
       ) do
    case ScriptStep.instance_data_command(step) do
      {:ok, command} ->
        effect = Effects.instance_data_command(world, command.field, command.value, command.mode, step.script_id)
        {Effects.enqueue(state, effect), blackboard}

      {:error, :unsupported} ->
        {state, blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :flee, datalong: seek}, _target, _now, %Context{} = context) do
    Flee.start(state, blackboard, context, seek != 0)
  end

  defp execute(state, blackboard, %ScriptStep{} = step, target_guid, now, %Context{}) do
    execute(state, blackboard, step, target_guid, now)
  end

  defp script_player_guid(source_guid, target_guid) do
    cond do
      Guid.entity_type(target_guid) == :player -> target_guid
      Guid.entity_type(source_guid) == :player -> source_guid
      true -> nil
    end
  end

  defp script_world_object_guid(source_guid, target_guid) do
    cond do
      Guid.entity_type(source_guid) != :player -> source_guid
      Guid.entity_type(target_guid) != :player -> target_guid
      true -> nil
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :remove_aura, datalong: spell_id}, _target_guid, now)
       when is_integer(spell_id) and spell_id > 0 do
    {state, events} = AuraCore.remove_spells(state, [spell_id], now)
    {Effects.enqueue(state, events), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :remove_aura}, _target_guid, _now) do
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :clear_auras}, _target_guid, now) do
    {state, events} = AuraCore.remove_on_evade(state, now)
    {Effects.enqueue(state, events), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :stop_scripts}, _target_guid, _now) do
    {Run.clear(state), blackboard}
  end

  defp execute(%Mob{internal: internal} = state, blackboard, %ScriptStep{command: :set_concealed} = step, _target, _now) do
    {Entity.mark_broadcast_update(%{state | internal: %{internal | concealed?: step.datalong != 0}}), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :modify_flags} = step, _target_guid, _now) do
    state =
      case step.datalong do
        46 -> %{state | unit: %{state.unit | flags: modify_flags(state.unit.flags, step)}}
        147 -> %{state | unit: %{state.unit | npc_flags: modify_flags(state.unit.npc_flags, step)}}
        _field -> state
      end

    {Entity.mark_broadcast_update(state), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :modify_flags} = step, _target_guid, _now) do
    state =
      if step.datalong == 9 do
        %{state | game_object: %{state.game_object | flags: modify_flags(state.game_object.flags, step)}}
      else
        state
      end

    {Entity.mark_broadcast_update(state), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :set_faction, datalong: 0}, _target_guid, _now) do
    {TemporaryFaction.clear(state), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :set_faction} = step, _target_guid, _now) do
    {TemporaryFaction.set(state, step.datalong, step.datalong2), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_melee_attack, datalong: enabled}, _target, _now) do
    {state, Blackboard.set_melee_enabled(blackboard, enabled != 0)}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_combat_movement, datalong: enabled}, _target, _now) do
    {state, Blackboard.set_combat_movement(blackboard, enabled != 0)}
  end

  defp execute(
         %{unit: %Unit{target: target}} = state,
         blackboard,
         %ScriptStep{command: :call_for_help, position: {radius, _y, _z, _o}},
         _target_guid,
         _now
       )
       when is_integer(target) and target > 0 and is_number(radius) and radius > 0 do
    {Effects.enqueue(state, Effects.call_for_help(target, radius)), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :call_for_help}, _target_guid, _now) do
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :summon_object} = step, _target_guid, _now) do
    position = step.position |> Tuple.to_list() |> Enum.map(&unspecified_coordinate/1) |> List.to_tuple()
    owned? = step.datalong3 != @unattached_object
    effect = Effects.summon_game_object(step.datalong, step.datalong2 * 1_000, position: position, owned?: owned?)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(
         %Mob{} = state,
         blackboard,
         %ScriptStep{command: :join_creature_group, position: {distance, _, _, angle}} = step,
         target,
         _now
       )
       when is_integer(target) and is_number(distance) and distance >= 0 and is_number(angle) do
    member = %Member{distance: distance, angle: angle, flags: step.datalong}
    {Effects.enqueue(state, Effects.creature_group_command({:join, target, member})), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :leave_creature_group}, _target, _now) do
    {Effects.enqueue(state, Effects.creature_group_command(:leave)), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :set_game_object_state} = step, _target, _now) do
    {GameObjectActions.set_state(state, step.datalong), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :play_custom_animation} = step, _target, _now) do
    effect = Effects.game_object_custom_animation(step.datalong)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(
         %{object: %{guid: guid}, unit: %Unit{level: level}} = state,
         blackboard,
         %ScriptStep{command: :add_aura, datalong: spell_id},
         _target_guid,
         _now
       )
       when is_integer(spell_id) and spell_id > 0 do
    effect = Effects.trigger_spell(guid, level || 1, guid, spell_id)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :respawn_creature} = step, _target, _now) do
    {Effects.enqueue(state, Effects.respawn_self(step.datalong != 0)), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :remove_object}, _target, _now)
       when is_struct(state, Mob) or is_struct(state, GameObject) do
    {Effects.enqueue(state, Effects.remove_self()), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :combat_stop}, _target, now) do
    %Engagement.Result{entity: state} = Engagement.leave(state, :script, now, blackboard: blackboard)
    {state, state.internal.blackboard}
  end

  defp execute(%Character{} = state, blackboard, %ScriptStep{command: :combat_stop}, _target, _now) do
    {state, effects} = PlayerCombat.disengage(state)
    {Effects.enqueue(state, effects), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :create_item} = step, target_guid, _now) do
    case script_player_guid(state.object.guid, target_guid) do
      nil ->
        {state, blackboard}

      player_guid ->
        {Effects.enqueue(state, Effects.create_item(player_guid, step.datalong, step.datalong2)), blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :remove_item} = step, target_guid, _now) do
    case script_player_guid(state.object.guid, target_guid) do
      nil ->
        {state, blackboard}

      player_guid ->
        {Effects.enqueue(state, Effects.take_item(player_guid, step.datalong, max(step.datalong2, 1))), blackboard}
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :morph} = step, _target_guid, _now) do
    {morph(state, morph_display_id(state, step)), blackboard}
  end

  defp execute(
         %Mob{internal: %{creature: %Creature{} = creature} = internal} = state,
         blackboard,
         %ScriptStep{command: :set_fly, datalong: enabled},
         _target_guid,
         _now
       ) do
    creature = %{creature | script_flight: enabled != 0}
    {CreatureMovement.sync(%{state | internal: %{internal | creature: creature}}), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_run, datalong: datalong}, _target_guid, _now) do
    run? = datalong != 0
    state = %{state | internal: %{state.internal | running: run?}}
    {state, Blackboard.set_run_mode(blackboard, run?)}
  end

  defp execute(state, blackboard, %ScriptStep{command: :despawn} = step, _target_guid, _now) do
    {Effects.enqueue(state, Effects.despawn_self(step.datalong, step.datalong2 * 1_000)), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :set_health_pct, datalong: pct}, _target_guid, _now) do
    {Entity.set_health_pct(state, pct), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :lose_health, datalong: amount}, _target_guid, now) do
    {Entity.lose_health(state, amount, now), blackboard}
  end

  defp execute(
         %Mob{internal: %{creature: %Creature{} = creature} = internal} = state,
         blackboard,
         %ScriptStep{command: :set_regeneration, datalong: stats},
         _target_guid,
         _now
       ) do
    {%{state | internal: %{internal | creature: %{creature | regenerate_stats: stats}}}, blackboard}
  end

  @sound_flag_distance_dependent 0x2

  defp execute(state, blackboard, %ScriptStep{command: :play_sound} = step, _target_guid, _now)
       when step.datalong > 0 do
    event =
      if (step.datalong2 &&& @sound_flag_distance_dependent) == 0 do
        Effects.play_sound(step.datalong)
      else
        Effects.play_object_sound(step.datalong)
      end

    {Effects.enqueue(state, event), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :play_sound}, _target_guid, _now) do
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :mount} = step, _target_guid, _now) do
    {set_mount(state, mount_display_id(step)), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :stand_state} = step, _target_guid, _now) do
    {set_stand_state(state, step.datalong), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :enter_evade}, _target, _now) do
    state =
      if Entity.dead?(state),
        do: state,
        else: Effects.enqueue(state, %Effects.EnterEvade{target_guid: state.object.guid})

    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :enter_evade}, target, _now) do
    state =
      if is_integer(target) and target > 0 and Guid.entity_type(target) in [:mob, :pet],
        do: Effects.enqueue(state, %Effects.EnterEvade{target_guid: target}),
        else: state

    {state, blackboard}
  end

  defp execute(%{unit: %Unit{}} = state, blackboard, %ScriptStep{command: :set_sheath} = step, _target, _now) do
    {Sheath.put(state, step.datalong), blackboard}
  end

  defp execute(
         %Mob{internal: internal, unit: unit} = state,
         blackboard,
         %ScriptStep{command: :invincibility, datalong: health, datalong2: is_percent},
         _target,
         _now
       ) do
    threshold = if is_percent == 0, do: health, else: div(unit.max_health * health, 100)
    {%{state | internal: %{internal | invincibility_health_threshold: max(threshold, 0)}}, blackboard}
  end

  defp execute(
         %Mob{object: %{guid: guid}, unit: %Unit{max_health: max_health}} = state,
         blackboard,
         %ScriptStep{command: :deal_damage, datalong: damage, datalong2: is_percent},
         guid,
         now
       )
       when is_integer(max_health) do
    amount = if is_percent == 0, do: damage, else: ceil(max_health * damage / 100)
    {Entity.lose_health(state, amount, now), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :deal_damage}, _target_guid, _now), do: {state, blackboard}

  defp execute(state, blackboard, %ScriptStep{command: :turn_to, position: {_x, _y, _z, o}}, _target_guid, _now) do
    state =
      state
      |> set_facing_angle(o)
      |> Effects.enqueue(Effects.set_facing({:angle, o}))

    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_phase} = step, _target_guid, _now) do
    {state, put_phase(blackboard, set_phase_value(blackboard, step))}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_phase_range}, _target_guid, _now) do
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: {:unsupported, command}} = step, _target_guid, _now) do
    Logger.debug("Script #{step.script_id}: command #{command} unsupported, skipping")
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{} = step, _target_guid, _now) do
    Logger.debug("Script #{step.script_id}: command #{step.command} unsupported for entity, skipping")
    {state, blackboard}
  end

  defp modify_flags(value, %ScriptStep{datalong2: flags, datalong3: 1}), do: (value || 0) ||| flags
  defp modify_flags(value, %ScriptStep{datalong2: flags, datalong3: 2}), do: (value || 0) &&& bnot(flags)

  defp modify_flags(value, %ScriptStep{datalong2: flags}) do
    value = value || 0
    if (value &&& flags) == 0, do: value ||| flags, else: value &&& bnot(flags)
  end

  defp halt_scripted_movement(state, now) do
    if Movement.moving?(state, now) do
      Movement.stop(state, now)
    else
      state
    end
  end

  defp server_controlled_teleport_source?(%Mob{
         unit: %Unit{flags: flags},
         movement_block: %{position: {x, y, z, o}},
         internal: %{world: %WorldRef{}, visibility_cell: visibility_cell, pet: pet}
       }) do
    not is_nil(visibility_cell) and not player_controlled?(flags, pet) and
      Enum.all?([x, y, z, o], &is_number/1)
  end

  defp server_controlled_teleport_source?(%Mob{}), do: false

  defp player_controlled?(_flags, %Pet{possessed?: true}), do: true
  defp player_controlled?(flags, _pet) when is_integer(flags), do: (flags &&& @unit_flag_player_controlled) != 0
  defp player_controlled?(_flags, _pet), do: false

  defp interrupt_casts(%{internal: %{casting: nil}} = state, _spell_id, _now), do: state

  defp interrupt_casts(%{internal: %{casting: casting}} = state, spell_id, now) do
    if spell_id == 0 or Cast.spell_id(casting) == spell_id, do: Casting.cancel(state, now), else: state
  end

  defp interrupt_casts(state, _spell_id, _now), do: state

  defp unspecified_coordinate(value) when value == 0, do: nil
  defp unspecified_coordinate(value), do: value

  defp home_position(%Mob{}, %ScriptStep{datalong: 0, position: position}), do: position

  defp home_position(%Mob{movement_block: %{position: position}}, %ScriptStep{datalong: 1}), do: position

  defp home_position(%Mob{internal: %{spawn: %{movement_block: %{position: position}}}}, %ScriptStep{datalong: 2}),
    do: position

  defp home_position(%Mob{}, %ScriptStep{}), do: nil

  defp talk(state, %{chat_type: chat_type} = text, target_guid) when chat_type in [:whisper, :boss_whisper] do
    if is_integer(target_guid) and Guid.entity_type(target_guid) == :player,
      do: Effects.enqueue(state, Effects.monster_talk(text.text, chat_type, target_guid)),
      else: state
  end

  defp talk(state, text, target_guid) do
    state = Effects.enqueue(state, Effects.monster_talk(text.text, text.chat_type, target_guid))

    case text do
      %{emote_id: emote_id} when is_integer(emote_id) and emote_id > 0 ->
        Effects.enqueue(state, Effects.emote(emote_id))

      _ ->
        state
    end
  end

  defp resolve_summon_position(%{position: {x, y, z, _o}} = summon, _state) when x != 0.0 or y != 0.0 or z != 0.0 do
    summon
  end

  defp resolve_summon_position(summon, %{movement_block: %{position: position}}) do
    %{summon | position: position}
  end

  defp resolve_summon_attack(_state, %ScriptStep{} = step, _target_guid, %Context{})
       when is_nil(step.dataint3) or step.dataint3 < 0 do
    nil
  end

  defp resolve_summon_attack(state, %ScriptStep{} = step, target_guid, %Context{} = context) do
    attack_step = %{step | target_type: ScriptStep.decode_target_type(step.dataint3), target_self?: false}
    resolve_target(state, attack_step, target_guid, context)
  end

  defp summon_count(_state, count, %Context{}) when is_integer(count), do: max(count, 0)

  defp summon_count(state, {:threat_players, ratio, least, most}, %Context{perception: perception}) do
    players =
      Enum.count(Threat.targets(state), fn guid ->
        Guid.entity_type(guid) == :player and match?(%{alive?: true}, Perception.metadata(perception, guid))
      end)

    (players * ratio) |> trunc() |> max(least) |> min(most)
  end

  defp choose_start_script(%ScriptStep{} = step, random) do
    step
    |> ScriptStep.start_script_options()
    |> choose_option(Random.integer(random, 100), 0)
  end

  defp choose_option([], _roll, _sum), do: nil

  defp choose_option([{id, chance} | rest], roll, sum) do
    if roll > sum and roll <= sum + chance do
      id
    else
      choose_option(rest, roll, sum + chance)
    end
  end

  defp morph_display_id(%{unit: %Unit{native_display_id: native}}, %ScriptStep{datalong: 0}), do: native

  defp morph_display_id(_state, %ScriptStep{datalong: display_id, datalong2: is_display_id}) when is_display_id != 0 do
    display_id
  end

  defp morph_display_id(_state, %ScriptStep{} = step) do
    Logger.debug("Script #{step.script_id}: morph by creature entry unsupported, skipping")
    nil
  end

  defp morph(%{unit: %Unit{display_id: current}} = state, display_id)
       when is_integer(display_id) and display_id > 0 and display_id != current do
    if Entity.dead?(state) do
      state
    else
      %{state | unit: %{state.unit | display_id: display_id}}
      |> Entity.mark_broadcast_update()
    end
  end

  defp morph(state, _display_id), do: state

  defp mount_display_id(%ScriptStep{datalong: 0}), do: 0

  defp mount_display_id(%ScriptStep{datalong: display_id, datalong2: is_display_id}) when is_display_id != 0 do
    display_id
  end

  defp mount_display_id(%ScriptStep{} = step) do
    Logger.debug("Script #{step.script_id}: mount by creature entry unresolved, skipping")
    nil
  end

  defp set_mount(%{unit: %Unit{mount_display_id: current} = unit} = state, display_id)
       when is_integer(display_id) and display_id != current do
    %{state | unit: %{unit | mount_display_id: display_id}}
    |> Entity.mark_broadcast_update()
  end

  defp set_mount(state, _display_id), do: state

  defp set_stand_state(%{unit: %Unit{stand_state: current} = unit} = state, stand_state)
       when is_integer(stand_state) and stand_state != current do
    %{state | unit: %{unit | stand_state: stand_state}}
    |> Entity.mark_broadcast_update()
  end

  defp set_stand_state(state, _stand_state), do: state

  defp set_facing_angle(%{movement_block: %{position: {x, y, z, _o}} = movement_block} = state, angle)
       when is_number(angle) do
    %{state | movement_block: %{movement_block | position: {x, y, z, angle}}}
  end

  defp set_facing_angle(state, _angle), do: state

  defp face_observed_target(%{internal: %{world: world}} = state, guid, perception) do
    case Perception.position(perception, guid) do
      {^world, x, y, _z} -> Movement.face_towards(state, {x, y})
      _missing -> state
    end
  end

  defp trigger_cast(
         %{object: %{guid: guid}, unit: %Unit{level: level}} = state,
         %CreatureSpell{} = entry,
         target_guid,
         %Context{}
       ) do
    Effects.enqueue(state, Effects.trigger_spell(guid, level, target_guid, entry.spell_id))
  end

  defp pick_talk_text(%ScriptStep{texts: [_ | _] = texts}, random), do: Random.choice(random, texts)
  defp pick_talk_text(%ScriptStep{}, _random), do: nil

  defp set_phase_value(%Blackboard{event_ai: %Blackboard.EventAI{phase: phase}}, %ScriptStep{
         datalong: value,
         datalong2: 1
       }) do
    phase + value
  end

  defp set_phase_value(%Blackboard{event_ai: %Blackboard.EventAI{phase: phase}}, %ScriptStep{
         datalong: value,
         datalong2: 2
       }) do
    phase - value
  end

  defp set_phase_value(%Blackboard{}, %ScriptStep{datalong: value}), do: value

  defp put_phase(%Blackboard{} = blackboard, phase) when is_integer(phase) do
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase |> max(0) |> min(@max_phase)}}
  end

  defp resolve_target(%{object: %{guid: guid}}, %ScriptStep{target_self?: true}, _provided), do: guid

  defp resolve_target(
         %{internal: %{pet: %{owner_guid: owner_guid}}},
         %ScriptStep{target_type: :owner_or_self},
         _provided
       )
       when is_integer(owner_guid) and owner_guid > 0 do
    owner_guid
  end

  defp resolve_target(%{object: %{guid: guid}}, %ScriptStep{target_type: :owner_or_self}, _provided), do: guid

  defp resolve_target(%{internal: %{pet: %{owner_guid: owner_guid}}}, %ScriptStep{target_type: :owner}, _provided)
       when is_integer(owner_guid) and owner_guid > 0 do
    owner_guid
  end

  defp resolve_target(%{unit: %Unit{summoned_by: owner_guid}}, %ScriptStep{target_type: :owner}, _provided)
       when is_integer(owner_guid) and owner_guid > 0 do
    owner_guid
  end

  defp resolve_target(_state, %ScriptStep{target_type: :provided}, provided), do: provided

  defp resolve_target(state, %ScriptStep{target_type: target_type}, _provided)
       when target_type in [
              :victim,
              :hostile_second_aggro,
              :hostile_last_aggro,
              :hostile_random,
              :hostile_random_not_top
            ] do
    victim(state)
  end

  defp resolve_target(_state, %ScriptStep{target_type: {:unsupported, target_type}} = step, _provided) do
    Logger.debug("Script #{step.script_id}: target type #{target_type} unsupported, skipping")
    nil
  end

  defp resolve_target(_state, %ScriptStep{}, _provided), do: nil

  defp resolve_target(state, %ScriptStep{target_type: target_type} = step, _provided, %Context{
         perception: perception,
         random: random
       })
       when target_type in [:nearest_creature_with_entry, :random_creature_with_entry] do
    find_creature_with_entry(state, step, target_type, perception, random)
  end

  defp resolve_target(state, %ScriptStep{target_type: target_type} = step, _provided, %Context{} = context)
       when target_type in [
              :hostile_second_aggro,
              :hostile_last_aggro,
              :hostile_random,
              :hostile_random_not_top,
              :hostile_nearest,
              :hostile_farthest
            ] do
    resolve_hostile_target(state, step, context)
  end

  defp resolve_target(state, %ScriptStep{target_type: target_type} = step, _provided, %Context{
         perception: perception,
         random: random
       })
       when target_type in [:nearest_game_object_with_entry, :random_game_object_with_entry] do
    find_game_object_with_entry(state, step, target_type, perception, random)
  end

  defp resolve_target(
         %{internal: %{pet: %Pet{owner_guid: owner}}} = state,
         %ScriptStep{target_type: :owner_hostile_random, target_param1: flags},
         _provided,
         %Context{perception: perception, random: random}
       ) do
    victim = victim(state)

    perception
    |> Perception.metadata(owner)
    |> Kernel.||(%{})
    |> Map.get(:combat_targets, [])
    |> Enum.filter(&(&1 != victim and target_flags_allow?(&1, flags, perception)))
    |> case do
      [] -> nil
      candidates -> Random.choice(random, candidates)
    end
  end

  defp resolve_target(_state, %ScriptStep{target_type: :nearest_player, target_param1: radius}, _provided, %Context{
         perception: perception
       }) do
    perception
    |> Perception.nearby(:players, positive_radius(radius, @default_buddy_radius))
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> case do
      {guid, _distance} -> guid
      nil -> nil
    end
  end

  defp resolve_target(state, %ScriptStep{target_type: target_type, target_param1: radius}, _provided, %Context{
         perception: perception
       })
       when target_type in [:nearest_hostile_player, :nearest_friendly_player] do
    source = Perception.actor(perception, state.object.guid)

    perception
    |> Perception.nearby(:players, positive_radius(radius, @default_buddy_radius))
    |> Enum.filter(fn {guid, _distance} ->
      player_reaction_allows?(target_type, source, Perception.actor(perception, guid))
    end)
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> case do
      {guid, _distance} -> guid
      nil -> nil
    end
  end

  defp resolve_target(state, %ScriptStep{target_type: target_type} = step, _provided, %Context{} = context)
       when target_type in [
              :friendly_injured,
              :friendly_injured_except,
              :friendly_missing_buff,
              :friendly_missing_buff_except
            ] do
    entry = %CreatureSpell{
      spell_id: ScriptStep.cast_spell_id(step) || 0,
      cast_target: target_type,
      target_param1: step.target_param1,
      target_param2: step.target_param2
    }

    MobSpells.resolve_target(state, entry, nil, context)
  end

  @map_event_target_types [:map_event_source, :map_event_target, :map_event_extra_target]

  defp resolve_target(
         _state,
         %ScriptStep{target_type: target_type, target_param1: event_id, target_param2: entry},
         _provided,
         %Context{script_targets: targets}
       )
       when target_type in @map_event_target_types do
    Map.get(targets, {target_type, event_id, entry})
  end

  defp resolve_target(
         _state,
         %ScriptStep{
           target_type: :creature_with_guid,
           target_param1: db_guid,
           target_param2: param2,
           buddy_guid: buddy_guid
         },
         _provided,
         %Context{script_targets: targets}
       ) do
    case Map.fetch(targets, {:creature_with_guid, db_guid, param2}) do
      {:ok, guid} -> guid
      :error -> buddy_guid
    end
  end

  defp resolve_target(
         _state,
         %ScriptStep{target_type: :creature_from_instance_data, target_param1: index, target_param2: param2},
         _provided,
         %Context{script_targets: targets}
       ) do
    Map.get(targets, {:creature_from_instance_data, index, param2})
  end

  defp resolve_target(
         _state,
         %ScriptStep{
           target_type: :game_object_with_guid,
           target_param1: db_guid,
           target_param2: param2,
           buddy_guid: buddy_guid
         },
         _provided,
         %Context{script_targets: targets}
       ) do
    case Map.fetch(targets, {:game_object_with_guid, db_guid, param2}) do
      {:ok, guid} when is_integer(guid) -> guid
      _unresolved -> buddy_guid
    end
  end

  defp resolve_target(state, %ScriptStep{} = step, provided, %Context{}) do
    resolve_target(state, step, provided)
  end

  defp victim(%{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  defp victim(_state), do: nil

  def observation_radius(steps) when is_list(steps) do
    Enum.reduce(steps, 0.0, fn
      %ScriptStep{} = step, radius ->
        max(radius, max(step_observation_radius(step), nested_observation_radius(step)))

      _step, radius ->
        radius
    end)
  end

  def observation_radius(_steps), do: 0.0

  def termination_conditions(steps) when is_list(steps) do
    steps
    |> Enum.flat_map(fn
      %ScriptStep{termination_condition: condition, sub_scripts: sub_scripts} ->
        [condition | sub_scripts |> Map.values() |> List.flatten() |> termination_conditions()]

      _step ->
        []
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def termination_conditions(_steps), do: []

  def zone_combat?(steps) when is_list(steps) do
    Enum.any?(steps, fn %ScriptStep{} = step ->
      step.command == :zone_combat_pulse or zone_combat?(step.sub_scripts |> Map.values() |> List.flatten())
    end)
  end

  def conditions(steps) when is_list(steps) do
    steps
    |> Enum.flat_map(fn
      %ScriptStep{} = step ->
        nested = step.sub_scripts |> Map.values() |> List.flatten() |> conditions()

        [
          step.condition,
          step.termination_condition,
          step.success_condition,
          step.failure_condition,
          step.target_condition
          | nested
        ]

      _step ->
        []
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def conditions(_steps), do: []

  def creature_entries(steps) when is_list(steps) do
    Enum.flat_map(steps, fn %ScriptStep{} = step ->
      own = if step.command == :update_entry, do: [step.datalong], else: []
      nested = step.sub_scripts |> Map.values() |> List.flatten() |> creature_entries()
      own ++ nested
    end)
    |> Enum.uniq()
  end

  def summon_entries(steps) when is_list(steps) do
    Enum.flat_map(steps, fn %ScriptStep{} = step ->
      own = if step.command == :summon_creature, do: [step.datalong], else: []
      nested = step.sub_scripts |> Map.values() |> List.flatten() |> summon_entries()
      own ++ nested
    end)
    |> Enum.uniq()
  end

  def random_point_requests(steps) when is_list(steps) do
    Enum.flat_map(steps, fn %ScriptStep{} = step ->
      nested = step.sub_scripts |> Map.values() |> List.flatten() |> random_point_requests()
      __MODULE__.MoveTo.request(step) ++ nested
    end)
    |> Enum.uniq()
  end

  def target_requests(steps) when is_list(steps) do
    steps
    |> Enum.flat_map(fn
      %ScriptStep{sub_scripts: sub_scripts} = step ->
        nested = sub_scripts |> Map.values() |> List.flatten() |> target_requests()
        target_request(step) ++ summon_attack_request(step) ++ nested

      _step ->
        []
    end)
    |> Enum.uniq()
  end

  def target_requests(_steps), do: []

  defp target_request(%ScriptStep{target_type: :creature_with_guid, target_param1: db_guid, target_param2: param2})
       when is_integer(db_guid) and db_guid > 0, do: [{:creature_with_guid, db_guid, param2}]

  defp target_request(%ScriptStep{target_type: :game_object_with_guid, target_param1: db_guid, target_param2: param2})
       when is_integer(db_guid) and db_guid > 0, do: [{:game_object_with_guid, db_guid, param2}]

  defp target_request(%ScriptStep{
         target_type: :creature_from_instance_data,
         target_param1: index,
         target_param2: param2
       })
       when is_integer(index) and index >= 0, do: [{:creature_from_instance_data, index, param2}]

  defp target_request(%ScriptStep{target_type: target_type, target_param1: event_id, target_param2: entry})
       when target_type in @map_event_target_types, do: [{target_type, event_id, entry}]

  defp target_request(%ScriptStep{}), do: []

  defp summon_attack_request(%ScriptStep{command: :summon_creature, dataint3: attack_type} = step)
       when is_integer(attack_type) and attack_type >= 0 do
    target_request(%{step | target_type: ScriptStep.decode_target_type(attack_type)})
  end

  defp summon_attack_request(%ScriptStep{}), do: []

  defp step_observation_radius(%ScriptStep{target_type: target_type, target_param2: radius})
       when target_type in @entry_target_types do
    positive_radius(radius, @default_buddy_radius)
  end

  defp step_observation_radius(%ScriptStep{target_type: target_type, target_param1: radius})
       when target_type in [
              :friendly_injured,
              :friendly_injured_except,
              :nearest_player,
              :nearest_hostile_player,
              :nearest_friendly_player
            ] do
    positive_radius(radius, @default_buddy_radius)
  end

  defp step_observation_radius(%ScriptStep{command: :terminate_script, datalong: entry, datalong2: radius})
       when entry > 0 do
    positive_radius(radius, @default_buddy_radius)
  end

  defp step_observation_radius(%ScriptStep{command: :flee, datalong: seek}) when seek != 0, do: Assistance.seek_radius()

  defp step_observation_radius(%ScriptStep{command: :summon_creature, positions: [_ | _]}), do: @summon_position_radius

  defp step_observation_radius(%ScriptStep{}), do: 0.0

  defp nested_observation_radius(%ScriptStep{sub_scripts: sub_scripts}) when is_map(sub_scripts) do
    sub_scripts
    |> Map.values()
    |> List.flatten()
    |> observation_radius()
  end

  defp nested_observation_radius(%ScriptStep{}), do: 0.0

  def game_object_observation_radius(steps) when is_list(steps) do
    Enum.reduce(steps, 0.0, fn
      %ScriptStep{} = step, radius ->
        max(radius, max(game_object_step_radius(step), nested_game_object_radius(step)))

      _step, radius ->
        radius
    end)
  end

  def game_object_observation_radius(_steps), do: 0.0

  defp game_object_step_radius(%ScriptStep{target_type: target_type, target_param2: radius})
       when target_type in [:nearest_game_object_with_entry, :random_game_object_with_entry] do
    positive_radius(radius, @default_buddy_radius)
  end

  defp game_object_step_radius(%ScriptStep{}), do: 0.0

  defp nested_game_object_radius(%ScriptStep{sub_scripts: sub_scripts}) when is_map(sub_scripts) do
    sub_scripts
    |> Map.values()
    |> List.flatten()
    |> game_object_observation_radius()
  end

  defp nested_game_object_radius(%ScriptStep{}), do: 0.0

  defp positive_radius(radius, _default) when is_number(radius) and radius > 0, do: radius / 1
  defp positive_radius(_radius, default), do: default

  defp positive_seconds(seconds) when is_integer(seconds) and seconds > 0, do: seconds * 1_000
  defp positive_seconds(_seconds), do: nil

  defp find_creature_with_entry(
         %{object: %{guid: self_guid}},
         %ScriptStep{target_param1: entry, target_param2: radius},
         target_type,
         perception,
         random
       ) do
    range = if is_number(radius) and radius > 0, do: radius, else: @default_buddy_radius

    candidates =
      perception
      |> Perception.nearby(:mobs, range)
      |> Enum.filter(fn {guid, _distance} -> guid != self_guid and Perception.entry(perception, guid) == entry end)

    case {target_type, candidates} do
      {_target_type, []} -> nil
      {:nearest_creature_with_entry, candidates} -> candidates |> Enum.min_by(&elem(&1, 1)) |> elem(0)
      {:random_creature_with_entry, candidates} -> random |> Random.choice(candidates) |> elem(0)
    end
  end

  defp find_game_object_with_entry(
         %{object: %{guid: self_guid}},
         %ScriptStep{target_param1: entry, target_param2: radius},
         target_type,
         perception,
         random
       ) do
    range = positive_radius(radius, @default_buddy_radius)

    candidates =
      perception
      |> Perception.nearby(:game_objects, range)
      |> Enum.filter(fn {guid, _distance} -> guid != self_guid and Perception.entry(perception, guid) == entry end)

    case {target_type, candidates} do
      {_target_type, []} -> nil
      {:nearest_game_object_with_entry, candidates} -> candidates |> Enum.min_by(&elem(&1, 1)) |> elem(0)
      {:random_game_object_with_entry, candidates} -> random |> Random.choice(candidates) |> elem(0)
    end
  end

  defp resolve_hostile_target(state, %ScriptStep{target_type: target_type, target_param1: flags}, %Context{} = context) do
    candidates =
      state
      |> Threat.entries()
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&target_flags_allow?(&1, flags, context.perception))

    select_hostile_target(target_type, candidates, context)
  end

  defp select_hostile_target(_target_type, [], %Context{}), do: nil
  defp select_hostile_target(:hostile_second_aggro, [_top, second | _rest], %Context{}), do: second
  defp select_hostile_target(:hostile_second_aggro, _candidates, %Context{}), do: nil
  defp select_hostile_target(:hostile_last_aggro, candidates, %Context{}), do: List.last(candidates)

  defp select_hostile_target(:hostile_random, candidates, %Context{random: random}) do
    Random.choice(random, candidates)
  end

  defp select_hostile_target(:hostile_random_not_top, [_top | rest], %Context{random: random}) when rest != [] do
    Random.choice(random, rest)
  end

  defp select_hostile_target(:hostile_random_not_top, _candidates, %Context{}), do: nil

  defp select_hostile_target(:hostile_nearest, candidates, %Context{perception: perception}) do
    distance_extreme(candidates, perception, :nearest)
  end

  defp select_hostile_target(:hostile_farthest, candidates, %Context{perception: perception}) do
    distance_extreme(candidates, perception, :farthest)
  end

  defp target_flags_allow?(guid, flags, perception) do
    (!flag?(flags, 0x001) or Perception.line_of_sight?(perception, guid)) and
      (!flag?(flags, 0x002) or Guid.entity_type(guid) == :player) and
      (!flag?(flags, 0x004) or match?(%{power_type: @mana_power}, Perception.metadata(perception, guid))) and
      (!flag?(flags, 0x200) or Guid.entity_type(guid) == :player)
  end

  defp flag?(flags, mask) when is_integer(flags), do: (flags &&& mask) != 0
  defp flag?(_flags, _mask), do: false

  defp player_reaction_allows?(:nearest_hostile_player, source, target),
    do: Hostility.valid_hostile_target?(source, target)

  defp player_reaction_allows?(:nearest_friendly_player, source, target), do: Hostility.friendly?(source, target)

  defp distance_extreme(candidates, perception, direction) do
    candidates
    |> Enum.flat_map(fn guid ->
      case Perception.distance(perception, guid) do
        distance when is_number(distance) -> [{guid, distance}]
        _missing -> []
      end
    end)
    |> case do
      [] -> nil
      distances when direction == :nearest -> distances |> Enum.min_by(&elem(&1, 1)) |> elem(0)
      distances -> distances |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end
end
