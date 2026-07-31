defmodule ThistleTea.Game.Entity.Logic.AI.Script do
  @moduledoc """
  Interpreter for generic vmangos script-command steps, shared by EventAI
  actions and waypoint scripts. `run/5` executes the immediately-due steps and
  defers delayed steps back to the owning process through a `script_steps`
  event; `execute_steps/5` runs a batch whose delay already elapsed. Commands
  act on the pure entity state — enqueueing chat/emote/cast/summon/despawn
  events, swapping the unit display id for morphs, recursing into resolved
  generic scripts for start-script steps, and mutating the blackboard phase,
  gait, or flee state — steps with a failing condition are skipped, and
  unsupported commands are logged and skipped. Steps flagged to swap final
  targets run on the resolved buddy creature instead: they are rewritten to
  provided-target form and forwarded to the buddy's owning process, matching
  vmangos source/target swap semantics. Casts honor the triggered cast flag: triggered and
  out-of-combat casts go through the trigger-spell pipeline, in-combat casts
  through the mob casting machinery.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.TemporaryFaction
  alias ThistleTea.Game.Guid

  require Logger

  @flee_duration_ms 7_000
  @flee_text "%s attempts to run away in fear!"
  @max_phase 31
  @scripted_event_commands [
    :start_map_event,
    :end_map_event,
    :add_map_event_target,
    :remove_map_event_target,
    :set_map_event_data,
    :send_map_event,
    :start_script_for_all,
    :edit_map_event
  ]

  def flee_duration_ms, do: @flee_duration_ms

  def run(state, %Blackboard{} = blackboard, steps, target_guid, now) when is_list(steps) and is_integer(now) do
    run(state, blackboard, steps, target_guid, Context.new(now))
  end

  def run(state, %Blackboard{} = blackboard, steps, target_guid, %Context{} = context) when is_list(steps) do
    {due, delayed} = Enum.split_with(steps, &(&1.delay_ms <= 0))
    {state, blackboard} = execute_steps(state, blackboard, due, target_guid, context)
    {schedule_delayed(state, delayed, target_guid), blackboard}
  end

  def execute_steps(state, %Blackboard{} = blackboard, steps, target_guid, now)
      when is_list(steps) and is_integer(now) do
    execute_steps(state, blackboard, steps, target_guid, Context.new(now))
  end

  def execute_steps(state, %Blackboard{} = blackboard, steps, target_guid, %Context{} = context) when is_list(steps) do
    Enum.reduce(steps, {state, blackboard}, fn %ScriptStep{} = step, {state, blackboard} ->
      dispatch(state, blackboard, step, target_guid, context)
    end)
  end

  defp dispatch(
         %{object: %{guid: self_guid}} = state,
         blackboard,
         %ScriptStep{swap_final?: true} = step,
         target_guid,
         %Context{} = context
       ) do
    case resolve_target(state, step, target_guid, context) do
      ^self_guid ->
        dispatch(state, blackboard, %{step | swap_final?: false}, target_guid, context)

      buddy_guid when is_integer(buddy_guid) and buddy_guid > 0 ->
        forward_to_buddy(state, blackboard, step, buddy_guid, target_guid)

      _ ->
        {state, blackboard}
    end
  end

  defp dispatch(state, blackboard, %ScriptStep{swap_initial?: true} = step, _target_guid, %Context{}) do
    Logger.debug("Script #{step.script_id}: swap-initial-targets unsupported, skipping")
    {state, blackboard}
  end

  defp dispatch(state, blackboard, %ScriptStep{} = step, target_guid, %Context{now: now} = context) do
    if ConditionLogic.met?(state, step.condition) do
      execute(state, blackboard, step, target_guid, now, context)
    else
      {state, blackboard}
    end
  end

  defp forward_to_buddy(
         %{object: %{guid: self_guid}} = state,
         blackboard,
         %ScriptStep{} = step,
         buddy_guid,
         target_guid
       ) do
    if Guid.entity_type(buddy_guid) in [:mob, :game_object] do
      forwarded = %{
        step
        | swap_initial?: false,
          swap_final?: false,
          target_self?: false,
          target_type: :provided,
          delay_ms: 0
      }

      provided = if step.swap_initial?, do: target_guid, else: self_guid
      {Effects.enqueue(state, Effects.forward_script_steps(buddy_guid, [forwarded], provided)), blackboard}
    else
      Logger.debug("Script #{step.script_id}: swap-final target is not a creature, skipping")
      {state, blackboard}
    end
  end

  defp schedule_delayed(state, [], _target_guid), do: state

  defp schedule_delayed(state, delayed, target_guid) do
    delayed
    |> Enum.group_by(& &1.delay_ms)
    |> Enum.reduce(state, fn {delay_ms, steps}, state ->
      Effects.enqueue(state, Effects.script_steps(steps, target_guid, delay_ms))
    end)
  end

  defp execute(
         state,
         blackboard,
         %ScriptStep{command: :move_to, datalong: 0, position: {x, y, z, _o}},
         _target,
         _now,
         %Context{} = context
       ) do
    {Navigation.move_to(state, {x, y, z}, [], context), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :start_waypoints} = step, _target_guid, now, %Context{
         waypoints: waypoints
       }) do
    cond do
      Core.dead?(state) ->
        {state, blackboard}

      route = Waypoints.resolve(waypoints, state, step) ->
        {state, Blackboard.start_waypoints(blackboard, route, max(step.datalong3, 0), now)}

      true ->
        {state, blackboard}
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
         %Mob{} = state,
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

  defp execute(state, blackboard, %ScriptStep{command: :cast_spell} = step, target_guid, _now, %Context{} = context) do
    entry = CreatureSpell.from_script_step(step)
    target = resolve_target(state, step, target_guid, context)

    cond do
      is_nil(target) or entry.spell_id <= 0 ->
        {state, blackboard}

      CreatureSpell.flag?(entry, :triggered) ->
        {trigger_cast(state, entry, target, context), blackboard}

      true ->
        MobSpells.attempt_scripted_cast(state, blackboard, entry, target, context)
    end
  end

  defp execute(state, blackboard, %ScriptStep{command: :start_waypoints}, _target_guid, _now, %Context{}) do
    {state, blackboard}
  end

  defp execute(
         %{object: %{guid: source_guid}, internal: %{world: world}} = state,
         blackboard,
         %ScriptStep{command: command} = step,
         target_guid,
         _now,
         %Context{}
       )
       when command in @scripted_event_commands do
    effect = Effects.scripted_event_command(world, source_guid, target_guid, step)
    {Effects.enqueue(state, effect), blackboard}
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

    navigation = %{blackboard.navigation | scripted_waypoint_route: nil}
    blackboard = blackboard |> then(&%{&1 | navigation: navigation}) |> Blackboard.clear_waypoint()
    {%{state | internal: %{internal | spawn: spawn}}, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_default_movement}, _target_guid, _now, %Context{}) do
    {state, blackboard}
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
    {state, events} = AuraLogic.remove_spells(state, [spell_id], now)
    {Effects.enqueue(state, events), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :remove_aura}, _target_guid, _now) do
    {state, blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :modify_flags} = step, _target_guid, _now) do
    state =
      case step.datalong do
        46 -> %{state | unit: %{state.unit | flags: modify_flags(state.unit.flags, step)}}
        147 -> %{state | unit: %{state.unit | npc_flags: modify_flags(state.unit.npc_flags, step)}}
        _field -> state
      end

    {Core.mark_broadcast_update(state), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :modify_flags} = step, _target_guid, _now) do
    state =
      if step.datalong == 9 do
        %{state | game_object: %{state.game_object | flags: modify_flags(state.game_object.flags, step)}}
      else
        state
      end

    {Core.mark_broadcast_update(state), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :set_faction, datalong: 0}, _target_guid, _now) do
    {TemporaryFaction.clear(state), blackboard}
  end

  defp execute(%Mob{} = state, blackboard, %ScriptStep{command: :set_faction} = step, _target_guid, _now) do
    {TemporaryFaction.set(state, step.datalong, step.datalong2), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :summon_object} = step, _target_guid, _now) do
    effect = Effects.summon_game_object(step.datalong, step.datalong2 * 1_000, position: step.position)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :set_game_object_state} = step, _target, _now) do
    state = %{state | game_object: %{state.game_object | state: step.datalong}}
    {Core.mark_broadcast_update(state), blackboard}
  end

  defp execute(%GameObject{} = state, blackboard, %ScriptStep{command: :play_custom_animation} = step, _target, _now) do
    effect = Effects.game_object_custom_animation(step.datalong)
    {Effects.enqueue(state, effect), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :morph} = step, _target_guid, _now) do
    {morph(state, morph_display_id(state, step)), blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: :set_run, datalong: datalong}, _target_guid, _now) do
    run? = datalong != 0
    state = %{state | internal: %{state.internal | running: run?}}
    {state, Blackboard.set_run_mode(blackboard, run?)}
  end

  defp execute(state, blackboard, %ScriptStep{command: :despawn} = step, _target_guid, _now) do
    {Effects.enqueue(state, Effects.despawn_self(step.datalong, step.datalong2 * 1_000)), blackboard}
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

  defp execute(state, blackboard, %ScriptStep{command: :flee}, _target_guid, now) do
    flee(state, blackboard, now)
  end

  defp execute(state, blackboard, %ScriptStep{command: :move_to} = step, _target_guid, _now) do
    Logger.debug("Script #{step.script_id}: move_to coordinate type #{step.datalong} unsupported, skipping")
    {state, blackboard}
  end

  defp execute(state, blackboard, %ScriptStep{command: {:unsupported, command}} = step, _target_guid, _now) do
    Logger.debug("Script #{step.script_id}: command #{command} unsupported, skipping")
    {state, blackboard}
  end

  defp modify_flags(value, %ScriptStep{datalong2: flags, datalong3: 1}), do: (value || 0) ||| flags
  defp modify_flags(value, %ScriptStep{datalong2: flags, datalong3: 2}), do: (value || 0) &&& bnot(flags)

  defp modify_flags(value, %ScriptStep{datalong2: flags}) do
    value = value || 0
    if (value &&& flags) == 0, do: value ||| flags, else: value &&& bnot(flags)
  end

  defp talk(state, %{chat_type: chat_type}, _target_guid) when chat_type in [:whisper, :boss_whisper] do
    Logger.debug("Script talk: whisper chat type unsupported, skipping")
    state
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

  defp choose_start_script(%ScriptStep{} = step, random) do
    step
    |> ScriptStep.start_script_options()
    |> choose_start_script(Random.integer(random, 100), 0)
  end

  defp choose_start_script([], _roll, _sum), do: nil

  defp choose_start_script([{script_id, chance} | rest], roll, sum) do
    if roll > sum and roll <= sum + chance do
      script_id
    else
      choose_start_script(rest, roll, sum + chance)
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
    if Core.dead?(state) do
      state
    else
      %{state | unit: %{state.unit | display_id: display_id}}
      |> Core.mark_broadcast_update()
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
    |> Core.mark_broadcast_update()
  end

  defp set_mount(state, _display_id), do: state

  defp set_stand_state(%{unit: %Unit{stand_state: current} = unit} = state, stand_state)
       when is_integer(stand_state) and stand_state != current do
    %{state | unit: %{unit | stand_state: stand_state}}
    |> Core.mark_broadcast_update()
  end

  defp set_stand_state(state, _stand_state), do: state

  defp set_facing_angle(%{movement_block: %{position: {x, y, z, _o}} = movement_block} = state, angle)
       when is_number(angle) do
    %{state | movement_block: %{movement_block | position: {x, y, z, angle}}}
  end

  defp set_facing_angle(state, _angle), do: state

  defp flee(%{unit: %Unit{target: target}} = state, %Blackboard{} = blackboard, now)
       when is_integer(target) and target > 0 do
    if Core.dead?(state) do
      {state, blackboard}
    else
      state = Effects.enqueue(state, Effects.monster_talk(@flee_text, :text_emote, target))
      {state, Blackboard.start_flee(blackboard, target, @flee_duration_ms, now)}
    end
  end

  defp flee(state, blackboard, _now), do: {state, blackboard}

  defp trigger_cast(
         %{object: %{guid: guid}, unit: %Unit{level: level}} = state,
         %CreatureSpell{} = entry,
         target_guid,
         %Context{} = context
       ) do
    if MobSpells.flags_allow?(state, entry, target_guid, context) do
      Effects.enqueue(state, Effects.trigger_spell(guid, level, target_guid, entry.spell_id))
    else
      state
    end
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
  defp resolve_target(%{object: %{guid: guid}}, %ScriptStep{target_type: :owner_or_self}, _provided), do: guid

  defp resolve_target(_state, %ScriptStep{target_type: :creature_with_guid, buddy_guid: buddy_guid}, _provided) do
    buddy_guid
  end

  defp resolve_target(state, %ScriptStep{target_type: :provided}, provided) do
    provided || victim(state)
  end

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

  defp resolve_target(state, %ScriptStep{} = step, provided, %Context{}) do
    resolve_target(state, step, provided)
  end

  defp victim(%{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  defp victim(_state), do: nil

  @default_buddy_radius 30.0

  def observation_radius(steps) when is_list(steps) do
    Enum.reduce(steps, 0.0, fn
      %ScriptStep{} = step, radius ->
        max(radius, max(step_observation_radius(step), nested_observation_radius(step)))

      _step, radius ->
        radius
    end)
  end

  def observation_radius(_steps), do: 0.0

  defp step_observation_radius(%ScriptStep{target_type: target_type, target_param2: radius})
       when target_type in [:nearest_creature_with_entry, :random_creature_with_entry] do
    positive_radius(radius, @default_buddy_radius)
  end

  defp step_observation_radius(%ScriptStep{target_type: target_type, target_param1: radius})
       when target_type in [:friendly_injured, :friendly_injured_except] do
    positive_radius(radius, @default_buddy_radius)
  end

  defp step_observation_radius(%ScriptStep{}), do: 0.0

  defp nested_observation_radius(%ScriptStep{sub_scripts: sub_scripts}) when is_map(sub_scripts) do
    sub_scripts
    |> Map.values()
    |> List.flatten()
    |> observation_radius()
  end

  defp nested_observation_radius(%ScriptStep{}), do: 0.0

  defp positive_radius(radius, _default) when is_number(radius) and radius > 0, do: radius / 1
  defp positive_radius(_radius, default), do: default

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
      |> Enum.filter(fn {guid, _distance} -> guid != self_guid and Guid.entry(guid) == entry end)

    case {target_type, candidates} do
      {_target_type, []} -> nil
      {:nearest_creature_with_entry, candidates} -> candidates |> Enum.min_by(&elem(&1, 1)) |> elem(0)
      {:random_creature_with_entry, candidates} -> random |> Random.choice(candidates) |> elem(0)
    end
  end
end
