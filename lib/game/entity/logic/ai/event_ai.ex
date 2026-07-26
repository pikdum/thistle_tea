defmodule ThistleTea.Game.Entity.Logic.AI.EventAI do
  @moduledoc """
  vmangos-style EventAI engine: evaluates a creature's `AIEvent` list and runs
  the firing events' action scripts through the script interpreter. Timed
  events (timers, HP/mana thresholds, range, friendly HP) are evaluated from
  `tick/3` on the creature's behavior-tree ticks with a one-second cadence;
  edge events (aggro, spawned, death, evade, kill, spell hit, leave combat,
  reached home) fire from the owning process at those moments. Events carrying a resolved
  condition tree are gated through the condition evaluator before their
  repeat timers are consumed, per vmangos ordering. Per-event enable/cooldown
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
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid

  @tick_ms 1_000
  @friendly_hp_default_radius 30.0

  def tick_ms, do: @tick_ms

  def events(%{internal: %Internal{creature: %Creature{ai_events: events}}}) when is_list(events), do: events
  def events(_state), do: []

  def with_blackboard(%{internal: %Internal{}} = state, fun) when is_function(fun, 2) do
    blackboard = Blackboard.from_any(state.internal.blackboard)
    {state, blackboard} = fun.(state, blackboard)
    %{state | internal: %{state.internal | blackboard: blackboard}}
  end

  def has_events?(state), do: events(state) != []

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
    matcher = fn %AIEvent{} = event ->
      event.event_type == :hit_by_spell and event.param1 in [0, spell_id]
    end

    fire_edges(state, blackboard, matcher, caster_guid, now, context)
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
         true <- AIEvent.phase_allows?(event, blackboard.eventai_phase),
         true <- casting_allows?(state, event),
         true <- ConditionLogic.met?(state, event.condition),
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

  defp satisfy(state, %AIEvent{event_type: :friendly_hp} = event, _invoker_guid, %Context{} = context) do
    with true <- in_combat?(state),
         friendly_guid when is_integer(friendly_guid) <- find_injured_friendly(state, event, context) do
      {:ok, friendly_guid}
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
       when event_type in [:aggro, :spawned, :death, :evade, :leave_combat, :hit_by_spell, :reached_home] do
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

  defp pct_within?(pct, %AIEvent{param1: max_pct, param2: min_pct}) when is_number(pct) do
    pct <= max_pct and pct >= min_pct
  end

  defp pct_within?(_pct, _event), do: false

  defp mana_pct(%{unit: %Unit{power1: mana, max_power1: max_mana}})
       when is_number(mana) and is_number(max_mana) and max_mana > 0 do
    mana * 100 / max_mana
  end

  defp mana_pct(_state), do: nil

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

  defp repeat_params(%AIEvent{event_type: event_type} = event)
       when event_type in [:timer_in_combat, :timer_ooc, :hp, :mana, :target_hp, :range, :friendly_hp, :hit_by_spell] do
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

  defp ensure_init(%Blackboard{eventai_timers: timers} = blackboard, _events, _now, %Context{}) when is_map(timers) do
    blackboard
  end

  defp ensure_init(%Blackboard{} = blackboard, events, now, %Context{} = context) do
    reset_ooc(%{blackboard | eventai_timers: %{}, eventai_disabled: MapSet.new()}, events, now, context)
  end

  defp reset_for_combat(%Blackboard{} = blackboard, events, now, %Context{random: random}) do
    blackboard = %{blackboard | eventai_timers: %{}, eventai_disabled: MapSet.new()}

    events
    |> Enum.with_index()
    |> Enum.reduce(blackboard, fn
      {%AIEvent{event_type: :timer_in_combat} = event, index}, blackboard ->
        put_timer(blackboard, index, now + Random.between(random, event.param1, event.param2))

      {%AIEvent{}, _index}, blackboard ->
        blackboard
    end)
  end

  defp reset_ooc(%Blackboard{eventai_timers: timers} = blackboard, events, now, %Context{random: random})
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

  defp enabled?(%Blackboard{eventai_disabled: %MapSet{} = disabled}, index) do
    not MapSet.member?(disabled, index)
  end

  defp enabled?(%Blackboard{}, _index), do: true

  defp disable(%Blackboard{eventai_disabled: %MapSet{} = disabled} = blackboard, index) do
    %{blackboard | eventai_disabled: MapSet.put(disabled, index)}
  end

  defp disable(%Blackboard{} = blackboard, index) do
    %{blackboard | eventai_disabled: MapSet.new([index])}
  end

  defp enable(%Blackboard{eventai_disabled: %MapSet{} = disabled} = blackboard, index) do
    %{blackboard | eventai_disabled: MapSet.delete(disabled, index)}
  end

  defp enable(%Blackboard{} = blackboard, _index), do: blackboard

  defp put_timer(%Blackboard{eventai_timers: timers} = blackboard, index, ready_at) do
    %{blackboard | eventai_timers: Map.put(timers || %{}, index, ready_at)}
  end

  defp due?(%Blackboard{} = blackboard, index, now) when is_integer(now) do
    case timer_at(blackboard, index) do
      nil -> true
      ready_at -> now >= ready_at
    end
  end

  defp timer_at(%Blackboard{eventai_timers: timers}, index) when is_map(timers) do
    Map.get(timers, index)
  end

  defp timer_at(%Blackboard{}, _index), do: nil

  defp victim(%{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  defp victim(_state), do: nil

  defp in_combat?(%{internal: %Internal{in_combat: true}}), do: true
  defp in_combat?(_state), do: false
end
