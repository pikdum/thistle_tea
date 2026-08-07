defmodule ThistleTea.Game.Entity.Logic.AI.EventAI do
  @moduledoc """
  vmangos-style EventAI engine: evaluates a creature's `AIEvent` list and runs
  the firing events' action scripts through the script interpreter. Timed
  events (timers, HP/mana thresholds, range, friendly HP) are evaluated from
  `tick/3` on the creature's behavior-tree ticks with a one-second cadence;
  edge events (aggro, spawned, death, evade, kill, spell hit, leave combat,
  reached home, scripted map event) fire from the owning process at those
  moments. Events carrying a resolved condition tree are gated through the
  condition evaluator before their repeat timers are consumed, per vmangos
  ordering. Per-event enable/cooldown
  state and the script-controlled phase live on the blackboard: non-repeatable
  events disable until the next combat entry, event timers re-roll from their
  repeat params, and out-of-combat timers re-initialize on evade, matching
  vmangos `CreatureEventAI` reset semantics.
  """
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.EventAI, as: EventMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionEvaluator
  alias ThistleTea.Game.Entity.Logic.Condition.EntityContext
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid

  @tick_ms 1_000
  @friendly_hp_default_radius 30.0
  @unconditional_events [
    :aggro,
    :spawned,
    :death,
    :evade,
    :leave_combat,
    :hit_by_spell,
    :reached_home,
    :receive_emote,
    :spell_hit_target,
    :script_event
  ]

  def tick_ms, do: @tick_ms

  def events(%{internal: %Internal{creature: %Creature{ai_events: events}}}) when is_list(events), do: events
  def events(_state), do: []

  def with_blackboard(%{internal: %Internal{}} = state, fun) when is_function(fun, 2) do
    blackboard = Blackboard.ensure(state.internal.blackboard)
    {state, blackboard} = fun.(state, blackboard)
    %{state | internal: %{state.internal | blackboard: blackboard}}
  end

  def has_events?(state), do: events(state) != []

  def observation_radius(state) do
    state
    |> events()
    |> Enum.reduce(0.0, fn %AIEvent{} = event, radius ->
      max(radius, max(event_observation_radius(event), actions_observation_radius(event)))
    end)
  end

  def game_object_observation_radius(state) do
    state
    |> events()
    |> Enum.flat_map(fn %AIEvent{actions: actions} -> List.flatten(actions) end)
    |> Script.game_object_observation_radius()
  end

  def script_target_requests(state) do
    state
    |> events()
    |> Enum.flat_map(fn %AIEvent{actions: actions} -> List.flatten(actions) end)
    |> Script.target_requests()
  end

  def conditions(state) do
    state
    |> events()
    |> Enum.flat_map(fn %AIEvent{condition: condition, actions: actions} ->
      [condition | actions |> List.flatten() |> Script.conditions()]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp event_observation_radius(%AIEvent{event_type: :friendly_hp, param2: radius})
       when is_number(radius) and radius > 0 do
    radius / 1
  end

  defp event_observation_radius(%AIEvent{event_type: :friendly_hp}), do: @friendly_hp_default_radius

  defp event_observation_radius(%AIEvent{event_type: event_type, param2: radius})
       when event_type in [:friendly_is_cc, :friendly_missing_buff] and is_number(radius) and radius > 0 do
    radius / 1
  end

  defp event_observation_radius(%AIEvent{event_type: :ooc_los, param2: radius}) when is_number(radius) and radius > 0 do
    radius / 1
  end

  defp event_observation_radius(%AIEvent{}), do: 0.0

  defp actions_observation_radius(%AIEvent{actions: actions}) when is_list(actions) do
    actions
    |> List.flatten()
    |> Script.observation_radius()
  end

  defp actions_observation_radius(%AIEvent{}), do: 0.0

  def tick(state, %Blackboard{} = blackboard, now) when is_integer(now) do
    tick(state, blackboard, now, Context.new(now))
  end

  def tick(state, %Blackboard{} = blackboard, now, %Context{} = context) when is_integer(now) do
    events = events(state)

    if events == [] or not Blackboard.ready_for?(blackboard, :next_eventai_at, now) do
      {state, blackboard}
    else
      blackboard =
        blackboard
        |> ensure_init(events, now, context)
        |> Blackboard.put_next_at(:next_eventai_at, @tick_ms, now)

      fire_matching(state, blackboard, events, &AIEvent.timed?/1, nil, now, context)
    end
  end

  def enter_combat(state, %Blackboard{} = blackboard, enemy_guid, now) when is_integer(now) do
    enter_combat(state, blackboard, enemy_guid, now, Context.new(now))
  end

  def enter_combat(state, %Blackboard{} = blackboard, enemy_guid, now, %Context{} = context) when is_integer(now) do
    events = events(state)

    if events == [] do
      {state, blackboard}
    else
      blackboard =
        blackboard
        |> ensure_init(events, now, context)
        |> reset_for_combat(events, now, context)

      fire_matching(state, blackboard, events, &(&1.event_type == :aggro), enemy_guid, now, context)
    end
  end

  def on_spawned(state, %Blackboard{} = blackboard, now) do
    on_spawned(state, blackboard, now, Context.new(now))
  end

  def on_spawned(state, %Blackboard{} = blackboard, now, %Context{} = context) do
    fire_edges(state, blackboard, :spawned, nil, now, context)
  end

  def on_death(state, %Blackboard{} = blackboard, killer_guid, now) do
    on_death(state, blackboard, killer_guid, now, Context.new(now))
  end

  def on_death(state, %Blackboard{} = blackboard, killer_guid, now, %Context{} = context) do
    fire_edges(state, blackboard, :death, killer_guid, now, context)
  end

  def on_kill(state, %Blackboard{} = blackboard, victim_guid, now) do
    on_kill(state, blackboard, victim_guid, now, Context.new(now))
  end

  def on_kill(state, %Blackboard{} = blackboard, victim_guid, now, %Context{} = context) do
    fire_edges(state, blackboard, :kill, victim_guid, now, context)
  end

  def on_leave_combat(state, %Blackboard{} = blackboard, now) do
    on_leave_combat(state, blackboard, now, Context.new(now))
  end

  def on_leave_combat(state, %Blackboard{} = blackboard, now, %Context{} = context) do
    fire_edges(state, blackboard, :leave_combat, nil, now, context)
  end

  def on_evade(state, %Blackboard{} = blackboard, now) do
    on_evade(state, blackboard, now, Context.new(now))
  end

  def on_evade(state, %Blackboard{} = blackboard, now, %Context{} = context) do
    {state, blackboard} = fire_edges(state, blackboard, :evade, nil, now, context)
    {state, reset_ooc(blackboard, events(state), now, context)}
  end

  def on_reached_home(state, %Blackboard{} = blackboard, now) do
    on_reached_home(state, blackboard, now, Context.new(now))
  end

  def on_reached_home(state, %Blackboard{} = blackboard, now, %Context{} = context) do
    fire_edges(state, blackboard, :reached_home, nil, now, context)
  end

  def on_spell_hit(state, %Blackboard{} = blackboard, caster_guid, spell_id, now) do
    on_spell_hit(state, blackboard, caster_guid, spell_id, now, Context.new(now))
  end

  def on_spell_hit(state, %Blackboard{} = blackboard, caster_guid, spell_id, now, %Context{} = context) do
    on_spell_hit(state, blackboard, caster_guid, spell_id, -1, now, context)
  end

  def on_spell_hit(state, %Blackboard{} = blackboard, caster_guid, spell_id, school_mask, now, %Context{} = context) do
    matcher = fn %AIEvent{} = event ->
      event.event_type == :hit_by_spell and event.param1 in [0, spell_id] and
        (event.param2 in [0, -1] or Bitwise.band(event.param2, school_mask) != 0)
    end

    fire_edges(state, blackboard, matcher, caster_guid, now, context)
  end

  def on_receive_emote(state, %Blackboard{} = blackboard, player_guid, emote_id, now, %Context{} = context) do
    matcher = fn %AIEvent{} = event ->
      event.event_type == :receive_emote and event.param1 == emote_id
    end

    fire_edges(state, blackboard, matcher, player_guid, now, context)
  end

  def on_spell_hit_target(
        state,
        %Blackboard{} = blackboard,
        target_guid,
        spell_id,
        school_mask,
        now,
        %Context{} = context
      ) do
    matcher = fn %AIEvent{} = event ->
      event.event_type == :spell_hit_target and event.param1 in [0, spell_id] and
        (event.param2 in [0, -1] or Bitwise.band(event.param2, school_mask) != 0)
    end

    fire_edges(state, blackboard, matcher, target_guid, now, context)
  end

  def on_script_event(state, %Blackboard{} = blackboard, event_id, data, now, %Context{} = context) do
    on_script_event(state, blackboard, event_id, data, nil, now, context)
  end

  def on_script_event(state, %Blackboard{} = blackboard, event_id, data, invoker_guid, now, %Context{} = context) do
    matcher = fn %AIEvent{} = event ->
      event.event_type == :script_event and event.param1 == event_id and event.param2 == data
    end

    fire_edges(state, blackboard, matcher, invoker_guid, now, context)
  end

  def ooc_timer_delay(state, %Blackboard{} = blackboard, now) when is_integer(now) do
    events = events(state)

    delays =
      events
      |> Enum.with_index()
      |> Enum.filter(fn {event, index} -> event.event_type == :timer_ooc and enabled?(blackboard, index) end)
      |> Enum.flat_map(fn {_event, index} ->
        case timer_at(blackboard, index) do
          ready_at when is_integer(ready_at) -> [max(ready_at - now, 0)]
          _ -> []
        end
      end)

    case delays do
      [] -> nil
      delays -> delays |> Enum.min() |> max(Blackboard.delay_until(blackboard, :next_eventai_at, now)) |> max(1)
    end
  end

  defp fire_edges(state, %Blackboard{} = blackboard, matcher, invoker_guid, now, %Context{} = context) do
    events = events(state)

    if events == [] do
      {state, blackboard}
    else
      blackboard = ensure_init(blackboard, events, now, context)
      fire_matching(state, blackboard, events, edge_matcher(matcher), invoker_guid, now, context)
    end
  end

  defp edge_matcher(matcher) when is_function(matcher, 1), do: matcher
  defp edge_matcher(event_type) when is_atom(event_type), do: &(&1.event_type == event_type)

  defp fire_matching(state, blackboard, events, matcher, invoker_guid, now, %Context{} = context) do
    events
    |> Enum.with_index()
    |> Enum.filter(fn {event, _index} -> matcher.(event) end)
    |> Enum.reduce({state, blackboard}, fn {event, index}, {state, blackboard} ->
      try_fire(state, blackboard, event, index, invoker_guid, now, context)
    end)
  end

  defp try_fire(state, %Blackboard{} = blackboard, %AIEvent{} = event, index, invoker_guid, now, %Context{} = context) do
    with true <- enabled?(blackboard, index),
         true <- due?(blackboard, index, now),
         true <- AIEvent.phase_allows?(event, blackboard.event_ai.phase),
         true <- casting_allows?(state, event),
         true <- condition_met?(state, event.condition, invoker_guid, context),
         {:ok, invoker_guid} <- satisfy(state, event, invoker_guid, context) do
      blackboard =
        blackboard
        |> update_repeat_timer(event, index, now, context)
        |> maybe_disable(event, index)

      if chance_passes?(event, context.random) do
        run_actions(state, blackboard, event, invoker_guid, context)
      else
        {state, blackboard}
      end
    else
      _ -> {state, blackboard}
    end
  end

  defp condition_met?(_state, nil, _invoker_guid, _context), do: true

  defp condition_met?(state, condition, invoker_guid, context) do
    state
    |> EntityContext.build(context, invoker_guid)
    |> ConditionEvaluator.evaluate(condition)
    |> Kernel.==(:met)
  end

  defp run_actions(state, %Blackboard{} = blackboard, %AIEvent{} = event, invoker_guid, %Context{} = context) do
    actions = if event.random_action?, do: [Random.choice(context.random, event.actions)], else: event.actions
    target_guid = invoker_guid || victim(state)

    Enum.reduce(actions, {state, blackboard}, fn steps, {state, blackboard} ->
      Script.run(state, blackboard, steps, target_guid, context)
    end)
  end

  defp satisfy(state, %AIEvent{event_type: :timer_in_combat}, invoker_guid, %Context{}) do
    if in_combat?(state), do: {:ok, invoker_guid}, else: :skip
  end

  defp satisfy(state, %AIEvent{event_type: :timer_ooc}, invoker_guid, %Context{}) do
    if in_combat?(state), do: :skip, else: {:ok, invoker_guid}
  end

  defp satisfy(state, %AIEvent{event_type: :hp} = event, invoker_guid, %Context{}) do
    if in_combat?(state) and pct_within?(Core.health_pct(state), event) do
      {:ok, invoker_guid}
    else
      :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :mana} = event, invoker_guid, %Context{}) do
    if in_combat?(state) and pct_within?(mana_pct(state), event) do
      {:ok, invoker_guid}
    else
      :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :target_hp} = event, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         %{health_pct: pct} when is_number(pct) <- Perception.metadata(perception, target),
         true <- pct_within?(pct, event) do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :target_mana} = event, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         %{mana_pct: pct} when is_number(pct) <- Perception.metadata(perception, target),
         true <- pct_within?(pct, event) do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :range} = event, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         distance when is_number(distance) <- Perception.distance(perception, target),
         true <- distance >= event.param1 and distance <= event.param2 do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :ooc_los} = event, _invoker_guid, %Context{} = context) do
    with false <- in_combat?(state),
         guid when is_integer(guid) <- find_ooc_los_unit(state, event, context) do
      {:ok, guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :friendly_hp} = event, _invoker_guid, %Context{} = context) do
    with true <- in_combat?(state),
         friendly_guid when is_integer(friendly_guid) <- find_injured_friendly(state, event, context) do
      {:ok, friendly_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :friendly_is_cc} = event, _invoker_guid, %Context{} = context) do
    if in_combat?(state) do
      case find_friendly(state, event.param2, context, &Map.get(&1, :crowd_controlled?, false)) do
        guid when is_integer(guid) -> {:ok, guid}
        _missing -> :skip
      end
    else
      :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :friendly_missing_buff} = event, _invoker_guid, %Context{} = context) do
    missing_buff? = fn metadata -> metadata |> Map.get(:aura_stacks, %{}) |> Map.get(event.param1, 0) == 0 end

    case find_friendly(state, event.param2, context, missing_buff?) do
      guid when is_integer(guid) -> {:ok, guid}
      _missing -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :aura} = event, invoker_guid, %Context{}) do
    if in_combat?(state) and aura_stacks(state, event.param1) >= event.param2,
      do: {:ok, invoker_guid},
      else: :skip
  end

  defp satisfy(state, %AIEvent{event_type: :missing_aura} = event, invoker_guid, %Context{}) do
    if in_combat?(state) and aura_stacks(state, event.param1) < event.param2,
      do: {:ok, invoker_guid},
      else: :skip
  end

  defp satisfy(state, %AIEvent{event_type: :target_aura} = event, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         stacks when is_integer(stacks) <- perceived_aura_stacks(perception, target, event.param1),
         true <- stacks >= event.param2 do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :target_missing_aura} = event, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         stacks when is_integer(stacks) <- perceived_aura_stacks(perception, target, event.param1),
         true <- stacks < event.param2 do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(state, %AIEvent{event_type: :victim_rooted}, invoker_guid, %Context{perception: perception}) do
    with true <- in_combat?(state),
         target when is_integer(target) <- victim(state),
         %{rooted?: true} <- Perception.metadata(perception, target) do
      {:ok, invoker_guid}
    else
      _ -> :skip
    end
  end

  defp satisfy(_state, %AIEvent{event_type: :kill} = event, invoker_guid, %Context{}) do
    if event.param3 == 1 and Guid.entity_type(invoker_guid) != :player do
      :skip
    else
      {:ok, invoker_guid}
    end
  end

  defp satisfy(_state, %AIEvent{event_type: event_type}, invoker_guid, %Context{})
       when event_type in @unconditional_events do
    {:ok, invoker_guid}
  end

  defp satisfy(_state, %AIEvent{}, _invoker_guid, %Context{}), do: :skip

  defp find_injured_friendly(state, %AIEvent{param2: radius}, %Context{} = context) do
    entry = %CreatureSpell{
      cast_target: :friendly_injured,
      target_param1: normalize_radius(radius),
      target_param2: 1
    }

    MobSpells.resolve_target(state, entry, nil, context)
  end

  defp normalize_radius(radius) when is_number(radius) and radius > 0, do: radius
  defp normalize_radius(_radius), do: @friendly_hp_default_radius

  defp find_ooc_los_unit(state, %AIEvent{param1: reaction, param2: radius}, %Context{perception: perception}) do
    source = Perception.actor(perception, state.object.guid)

    perception
    |> nearby_units(normalize_radius(radius))
    |> Enum.filter(fn {guid, _distance} ->
      Perception.line_of_sight?(perception, guid) and
        reaction_allows?(reaction, source, Perception.actor(perception, guid))
    end)
    |> Enum.min_by(&elem(&1, 1), fn -> nil end)
    |> case do
      {guid, _distance} -> guid
      nil -> nil
    end
  end

  defp nearby_units(perception, radius) do
    Perception.nearby(perception, :mobs, radius) ++ Perception.nearby(perception, :players, radius)
  end

  defp find_friendly(state, radius, %Context{perception: perception}, predicate) when is_function(predicate, 1) do
    source = Perception.actor(perception, state.object.guid)

    state
    |> friendly_candidates(perception, normalize_radius(radius))
    |> Enum.find_value(fn {guid, metadata} ->
      target = Map.put(metadata, :guid, guid)

      if friendly_candidate?(source, target) and predicate.(metadata), do: guid
    end)
  end

  defp friendly_candidates(state, perception, radius) do
    self_metadata = %{
      alive?: not Core.dead?(state),
      in_combat: in_combat?(state),
      unit_flags: state.unit.flags,
      aura_stacks: AuraLogic.spell_stacks(state),
      crowd_controlled?: AuraLogic.crowd_controlled?(state)
    }

    nearby =
      perception
      |> nearby_units(radius)
      |> Enum.flat_map(fn {guid, _distance} ->
        case Perception.metadata(perception, guid) do
          metadata when is_map(metadata) -> [{guid, metadata}]
          _missing -> []
        end
      end)

    [{state.object.guid, self_metadata} | nearby]
  end

  defp friendly_candidate?(source, %{alive?: true, in_combat: true} = target) do
    selectable?(Map.get(target, :unit_flags)) and not Hostility.hostile?(source, target)
  end

  defp friendly_candidate?(_source, _target), do: false

  defp selectable?(flags) when is_integer(flags), do: Bitwise.band(flags, 0x02000000) == 0
  defp selectable?(_flags), do: true

  defp reaction_allows?(0, _source, _target), do: true
  defp reaction_allows?(1, source, target), do: Hostility.hostile?(source, target)
  defp reaction_allows?(2, source, target), do: not Hostility.hostile?(source, target)
  defp reaction_allows?(_reaction, _source, _target), do: false

  defp aura_stacks(state, spell_id), do: state |> AuraLogic.spell_stacks() |> Map.get(spell_id, 0)

  defp perceived_aura_stacks(perception, guid, spell_id) do
    case Perception.metadata(perception, guid) do
      %{aura_stacks: stacks} when is_map(stacks) -> Map.get(stacks, spell_id, 0)
      _metadata -> 0
    end
  end

  defp pct_within?(pct, %AIEvent{param1: max_pct, param2: min_pct}) when is_number(pct) do
    pct <= max_pct and pct >= min_pct
  end

  defp pct_within?(_pct, _event), do: false

  defp mana_pct(state), do: Core.mana_pct(state)

  defp update_repeat_timer(%Blackboard{} = blackboard, %AIEvent{} = event, index, now, %Context{random: random}) do
    case repeat_params(event) do
      nil ->
        blackboard

      {min_ms, max_ms} when max_ms >= min_ms ->
        put_timer(blackboard, index, now + Random.between(random, min_ms, max_ms))

      _invalid ->
        disable(blackboard, index)
    end
  end

  defp repeat_params(%AIEvent{event_type: :kill} = event), do: {event.param1, event.param2}
  defp repeat_params(%AIEvent{event_type: :victim_rooted} = event), do: {event.param1, event.param2}

  defp repeat_params(%AIEvent{event_type: event_type} = event)
       when event_type in [
              :timer_in_combat,
              :timer_ooc,
              :hp,
              :mana,
              :target_hp,
              :target_mana,
              :range,
              :ooc_los,
              :friendly_hp,
              :friendly_is_cc,
              :friendly_missing_buff,
              :hit_by_spell,
              :spell_hit_target,
              :aura,
              :target_aura,
              :missing_aura,
              :target_missing_aura
            ] do
    {event.param3, event.param4}
  end

  defp repeat_params(%AIEvent{}), do: nil

  defp maybe_disable(%Blackboard{} = blackboard, %AIEvent{repeatable?: true}, _index), do: blackboard
  defp maybe_disable(%Blackboard{} = blackboard, %AIEvent{}, index), do: disable(blackboard, index)

  defp chance_passes?(%AIEvent{chance: chance}, random) when is_integer(chance) and chance < 100 do
    Random.integer(random, 100) <= chance
  end

  defp chance_passes?(%AIEvent{}, _random), do: true

  defp casting_allows?(state, %AIEvent{not_casting?: true}), do: is_nil(state.internal.casting)
  defp casting_allows?(_state, %AIEvent{}), do: true

  defp ensure_init(%Blackboard{event_ai: %EventMemory{timers: timers}} = blackboard, _events, _now, %Context{})
       when is_map(timers) do
    blackboard
  end

  defp ensure_init(%Blackboard{} = blackboard, events, now, %Context{} = context) do
    event_ai = %{blackboard.event_ai | timers: %{}, disabled: MapSet.new()}
    reset_ooc(%{blackboard | event_ai: event_ai}, events, now, context)
  end

  defp reset_for_combat(%Blackboard{} = blackboard, events, now, %Context{random: random}) do
    event_ai = %{blackboard.event_ai | timers: %{}, disabled: MapSet.new()}
    blackboard = %{blackboard | event_ai: event_ai}

    events
    |> Enum.with_index()
    |> Enum.reduce(blackboard, fn
      {%AIEvent{event_type: :timer_in_combat} = event, index}, blackboard ->
        put_timer(blackboard, index, now + Random.between(random, event.param1, event.param2))

      {%AIEvent{}, _index}, blackboard ->
        blackboard
    end)
  end

  defp reset_ooc(%Blackboard{event_ai: %EventMemory{timers: timers}} = blackboard, events, now, %Context{random: random})
       when is_map(timers) do
    events
    |> Enum.with_index()
    |> Enum.reduce(blackboard, fn
      {%AIEvent{event_type: :timer_ooc} = event, index}, blackboard ->
        blackboard
        |> put_timer(index, now + Random.between(random, event.param1, event.param2))
        |> enable(index)

      {%AIEvent{}, _index}, blackboard ->
        blackboard
    end)
  end

  defp reset_ooc(%Blackboard{} = blackboard, _events, _now, %Context{}), do: blackboard

  defp enabled?(%Blackboard{event_ai: %EventMemory{disabled: %MapSet{} = disabled}}, index) do
    not MapSet.member?(disabled, index)
  end

  defp enabled?(%Blackboard{}, _index), do: true

  defp disable(%Blackboard{event_ai: %EventMemory{disabled: %MapSet{} = disabled}} = blackboard, index) do
    %{blackboard | event_ai: %{blackboard.event_ai | disabled: MapSet.put(disabled, index)}}
  end

  defp disable(%Blackboard{} = blackboard, index) do
    %{blackboard | event_ai: %{blackboard.event_ai | disabled: MapSet.new([index])}}
  end

  defp enable(%Blackboard{event_ai: %EventMemory{disabled: %MapSet{} = disabled}} = blackboard, index) do
    %{blackboard | event_ai: %{blackboard.event_ai | disabled: MapSet.delete(disabled, index)}}
  end

  defp enable(%Blackboard{} = blackboard, _index), do: blackboard

  defp put_timer(%Blackboard{event_ai: %EventMemory{timers: timers}} = blackboard, index, ready_at) do
    %{blackboard | event_ai: %{blackboard.event_ai | timers: Map.put(timers || %{}, index, ready_at)}}
  end

  defp due?(%Blackboard{} = blackboard, index, now) when is_integer(now) do
    case timer_at(blackboard, index) do
      nil -> true
      ready_at -> now >= ready_at
    end
  end

  defp timer_at(%Blackboard{event_ai: %EventMemory{timers: timers}}, index) when is_map(timers) do
    Map.get(timers, index)
  end

  defp timer_at(%Blackboard{}, _index), do: nil

  defp victim(%{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  defp victim(_state), do: nil

  defp in_combat?(%{internal: %Internal{in_combat: true}}), do: true
  defp in_combat?(_state), do: false
end
