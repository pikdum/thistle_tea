defmodule ThistleTea.Game.World.System.ScriptedEvent do
  @moduledoc """
  Owns VMangos scripted map events, their timers, targets, mutable counters,
  condition checks, and success or failure script dispatch.
  """

  use GenServer

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Condition.Result
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Reputation
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.WorldRef

  require Logger

  defmodule Event do
    @moduledoc false
    defstruct [
      :id,
      :world,
      :source_guid,
      :target_guid,
      :expires_at,
      :success_condition,
      :failure_condition,
      :success_steps,
      :failure_steps,
      :token,
      data: %{},
      targets: []
    ]
  end

  defmodule Target do
    @moduledoc false
    defstruct [
      :guid,
      :success_condition,
      :failure_condition,
      :success_steps,
      :failure_steps
    ]
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  def command(%Effects.ScriptedEventCommand{} = effect), do: GenServer.cast(__MODULE__, {:command, effect})

  def condition_results(_world, _source_guid, _target_guid, []), do: %{}

  def condition_results(world, source_guid, target_guid, conditions) when is_list(conditions) do
    GenServer.call(__MODULE__, {:condition_results, WorldRef.coerce(world), source_guid, target_guid, conditions})
  end

  def target_results(_world, []), do: %{}

  def target_results(world, selectors) when is_list(selectors) do
    GenServer.call(__MODULE__, {:target_results, WorldRef.coerce(world), selectors})
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:condition_results, world, source_guid, target_guid, conditions}, _from, events) do
    results =
      Map.new(conditions, fn
        %Condition{} = condition ->
          {condition_key(condition), condition_result(condition, events, world, source_guid, target_guid)}
      end)

    {:reply, results, events}
  end

  def handle_call({:target_results, world, selectors}, _from, events) do
    results = Map.new(selectors, &{&1, event_target(events, world, &1)})
    {:reply, results, events}
  end

  @impl GenServer
  def handle_cast({:command, %Effects.ScriptedEventCommand{} = effect}, events) do
    {:noreply, apply_command(events, effect)}
  rescue
    error ->
      Logger.error("scripted event command crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, events}
  end

  @impl GenServer
  def handle_info({:evaluate, key, token}, events) do
    case Map.get(events, key) do
      %Event{token: ^token} = event -> {:noreply, evaluate(events, key, event)}
      _event -> {:noreply, events}
    end
  rescue
    error ->
      Logger.error("scripted event evaluation crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, events}
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :start_map_event}} = effect) do
    key = event_key(effect.world, effect.step.datalong)

    if Map.has_key?(events, key) do
      events
    else
      token = make_ref()

      event = %Event{
        id: effect.step.datalong,
        world: WorldRef.coerce(effect.world),
        source_guid: effect.source_guid,
        target_guid: effect.target_guid,
        expires_at: Time.now() + max(effect.step.datalong2, 0) * 1_000,
        success_condition: effect.step.success_condition,
        failure_condition: effect.step.failure_condition,
        success_steps: sub_steps(effect.step, effect.step.dataint2),
        failure_steps: sub_steps(effect.step, effect.step.dataint4),
        token: token
      }

      schedule(key, token)
      Map.put(events, key, event)
    end
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :end_map_event}} = effect) do
    end_event(events, event_key(effect.world, effect.step.datalong), effect.step.datalong2 != 0)
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :add_map_event_target}} = effect) do
    key = event_key(effect.world, effect.step.datalong)

    update_event(events, key, fn event ->
      target = %Target{
        guid: effect.source_guid,
        success_condition: effect.step.success_condition,
        failure_condition: effect.step.failure_condition,
        success_steps: sub_steps(effect.step, effect.step.dataint2),
        failure_steps: sub_steps(effect.step, effect.step.dataint4)
      }

      targets = [target | Enum.reject(event.targets, &(&1.guid == target.guid))]
      %{event | targets: targets}
    end)
  end

  defp apply_command(
         events,
         %Effects.ScriptedEventCommand{step: %ScriptStep{command: :remove_map_event_target}} = effect
       ) do
    key = event_key(effect.world, effect.step.datalong)

    update_event(events, key, fn event ->
      targets =
        remove_targets(
          event.targets,
          effect.step.datalong3,
          effect.step.target_condition,
          events,
          event.world,
          effect.source_guid
        )

      %{event | targets: targets}
    end)
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :set_map_event_data}} = effect) do
    key = event_key(effect.world, effect.step.datalong)

    update_event(events, key, fn event ->
      current = Map.get(event.data, effect.step.datalong2, 0)

      value =
        case effect.step.datalong4 do
          1 -> current + effect.step.datalong3
          2 -> max(current - effect.step.datalong3, 0)
          _type -> effect.step.datalong3
        end

      %{event | data: Map.put(event.data, effect.step.datalong2, value)}
    end)
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :send_map_event}} = effect) do
    case Map.get(events, event_key(effect.world, effect.step.datalong)) do
      %Event{} = event -> send_event(event, effect.step.datalong2, effect.step.datalong3)
      nil -> :ok
    end

    events
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :edit_map_event}} = effect) do
    key = event_key(effect.world, effect.step.datalong)

    update_event(events, key, fn event ->
      event
      |> edit_condition(:success_condition, effect.step.dataint, effect.step.success_condition)
      |> edit_steps(:success_steps, effect.step.dataint2, effect.step)
      |> edit_condition(:failure_condition, effect.step.dataint3, effect.step.failure_condition)
      |> edit_steps(:failure_steps, effect.step.dataint4, effect.step)
    end)
  end

  defp apply_command(events, %Effects.ScriptedEventCommand{step: %ScriptStep{command: :start_script_for_all}} = effect) do
    start_script_for_all(effect)
    events
  end

  defp apply_command(events, _effect), do: events

  defp event_target(events, world, {target_type, event_id, entry}) do
    case Map.get(events, event_key(world, event_id)) do
      %Event{} = event -> select_event_target(event, target_type, entry)
      nil -> nil
    end
  end

  defp select_event_target(%Event{source_guid: guid}, :map_event_source, _entry), do: guid
  defp select_event_target(%Event{target_guid: guid}, :map_event_target, _entry), do: guid

  defp select_event_target(%Event{targets: targets}, :map_event_extra_target, entry) do
    targets
    |> Enum.find(fn %Target{guid: guid} -> entry == 0 or Guid.entry(guid) == entry end)
    |> case do
      %Target{guid: guid} -> guid
      nil -> nil
    end
  end

  defp evaluate(events, key, %Event{} = event) do
    target_result = target_result(event, events)

    cond do
      Time.now() >= event.expires_at ->
        end_event(events, key, false)

      condition_met?(event.failure_condition, events, event.world, event.source_guid, event.target_guid) ->
        end_event(events, key, false)

      condition_met?(event.success_condition, events, event.world, event.source_guid, event.target_guid) ->
        end_event(events, key, true)

      target_result == :failure ->
        end_event(events, key, false)

      target_result == :success ->
        end_event(events, key, true)

      true ->
        schedule(key, event.token)
        events
    end
  end

  defp target_result(%Event{} = event, events) do
    Enum.find_value(event.targets, :none, &target_result(&1, event, events))
  end

  defp target_result(%Target{guid: guid}, _event, _events) when not is_integer(guid), do: nil

  defp target_result(%Target{} = target, %Event{} = event, events) do
    cond do
      not present?(target.guid) -> nil
      condition_met?(target.failure_condition, events, event.world, event.source_guid, target.guid) -> :failure
      condition_met?(target.success_condition, events, event.world, event.source_guid, target.guid) -> :success
      true -> nil
    end
  end

  defp end_event(events, key, success?) do
    case Map.pop(events, key) do
      {nil, events} ->
        events

      {%Event{} = event, events} ->
        run_event_steps(event, success?)

        events
    end
  end

  defp run_event_steps(%Event{} = event, success?) do
    run_steps(
      event.source_guid,
      if(success?, do: event.success_steps, else: event.failure_steps),
      event.target_guid
    )

    Enum.each(event.targets, &run_target_steps(&1, event, success?))
  end

  defp run_target_steps(%Target{} = target, %Event{} = event, success?) do
    if present?(target.guid) do
      steps = if success?, do: target.success_steps, else: target.failure_steps
      run_steps(target.guid, steps, event.target_guid)
    end
  end

  defp remove_targets(targets, 0, _condition, _events, _world, source_guid),
    do: Enum.reject(targets, &(&1.guid == source_guid))

  defp remove_targets(targets, 1, condition, events, world, source_guid) do
    {_removed?, targets} =
      Enum.reduce(targets, {false, []}, fn target, {removed?, kept} ->
        if not removed? and condition_met?(condition, events, world, target.guid, source_guid) do
          {true, kept}
        else
          {removed?, [target | kept]}
        end
      end)

    Enum.reverse(targets)
  end

  defp remove_targets(targets, 2, condition, events, world, source_guid) do
    Enum.reject(targets, &condition_met?(condition, events, world, &1.guid, source_guid))
  end

  defp remove_targets(_targets, 3, _condition, _events, _world, _source_guid), do: []
  defp remove_targets(targets, _mode, _condition, _events, _world, _source_guid), do: targets

  defp condition_met?(nil, _events, _world, _source_guid, _target_guid), do: false

  defp condition_met?(%Condition{} = condition, events, world, source_guid, target_guid) do
    condition_result(condition, events, world, source_guid, target_guid) == :met
  end

  defp condition_result(%Condition{} = condition, events, world, source_guid, target_guid) do
    {source_guid, target_guid} =
      if condition.swap_targets?, do: {target_guid, source_guid}, else: {source_guid, target_guid}

    result = evaluate_condition(condition, events, world, source_guid, target_guid)
    if condition.reverse?, do: Result.negate(result), else: result
  end

  defp evaluate_condition(%Condition{type: :none}, _events, _world, _source_guid, _target_guid), do: :met

  defp evaluate_condition(%Condition{type: :not, children: [child]}, events, world, source_guid, target_guid),
    do: child |> condition_result(events, world, source_guid, target_guid) |> Result.negate()

  defp evaluate_condition(%Condition{type: :or, children: children}, events, world, source_guid, target_guid),
    do: children |> Enum.map(&condition_result(&1, events, world, source_guid, target_guid)) |> Result.combine_or()

  defp evaluate_condition(%Condition{type: :and, children: children}, events, world, source_guid, target_guid),
    do: children |> Enum.map(&condition_result(&1, events, world, source_guid, target_guid)) |> Result.combine_and()

  defp evaluate_condition(
         %Condition{type: :escort, value1: flags, value2: distance} = condition,
         _events,
         world,
         source,
         target
       ) do
    []
    |> maybe_add_dead_result((flags &&& 0x1) != 0, condition, source)
    |> maybe_add_dead_result((flags &&& 0x2) != 0, condition, target)
    |> maybe_add_distance_result(distance > 0, condition, world, source, target, distance)
    |> Result.combine_or()
  end

  defp evaluate_condition(
         %Condition{type: :map_event_data, value1: id, value2: index, value3: expected, value4: comparison} = condition,
         events,
         world,
         _source,
         _target
       ) do
    value =
      case Map.get(events, event_key(world, id)) do
        %Event{data: data} -> Map.get(data, index, 0)
        nil -> nil
      end

    if is_integer(value), do: Result.compare_result(value, expected, comparison, condition), else: :unmet
  end

  defp evaluate_condition(%Condition{type: :map_event_active, value1: id}, events, world, _source, _target),
    do: Result.truth(Map.has_key?(events, event_key(world, id)))

  defp evaluate_condition(
         %Condition{type: :nearby_creature, value1: entry, value2: radius, value3: dead, value4: not_self} = condition,
         _events,
         world,
         source,
         target
       ) do
    case World.position(target) || World.position(source) do
      {^world, x, y, z} ->
        :mobs
        |> World.nearby_units_exact(world, {x, y, z}, radius)
        |> Enum.filter(fn {guid, _distance} -> Guid.entry(guid) == entry and (not_self == 0 or guid != target) end)
        |> Enum.map(&nearby_creature_result(condition, &1, dead))
        |> Result.combine_or()

      _missing ->
        Result.unknown(condition, {:missing_fact, :source_or_target, :position})
    end
  end

  defp evaluate_condition(
         %Condition{type: :nearby_game_object, value1: entry, value2: radius} = condition,
         _events,
         world,
         source,
         target
       ) do
    case World.position(target) || World.position(source) do
      {^world, x, y, z} ->
        result =
          :game_objects
          |> World.nearby_units_exact(world, {x, y, z}, radius)
          |> Enum.any?(fn {guid, _distance} -> Guid.entry(guid) == entry end)

        Result.truth(result)

      _missing ->
        Result.unknown(condition, {:missing_fact, :source_or_target, :position})
    end
  end

  defp evaluate_condition(
         %Condition{type: :map_event_targets, value1: id, children: [child]},
         events,
         world,
         source,
         _target
       ) do
    case Map.get(events, event_key(world, id)) do
      %Event{targets: targets} ->
        targets
        |> Enum.map(&event_target_condition_result(&1, child, events, world, source))
        |> Result.combine_and()

      nil ->
        :met
    end
  end

  defp evaluate_condition(%Condition{type: :alive} = condition, _events, _world, _source, target) do
    alive_result(condition, target)
  end

  defp evaluate_condition(
         %Condition{type: :reaction, value1: expected, value2: comparison} = condition,
         _events,
         _world,
         source,
         target
       ) do
    if reaction_available?(source, target) do
      rank = target |> Hostility.reaction_rank(source) |> Reputation.rank_value()
      Result.compare_result(rank, expected, comparison, condition)
    else
      Result.unknown(condition, {:missing_fact, :source_or_target, :reaction})
    end
  end

  defp evaluate_condition(%Condition{type: :object_spawned} = condition, _events, _world, _source, target) do
    metadata_result(condition, target, :go_spawned?)
  end

  defp evaluate_condition(
         %Condition{type: :object_loot_state, value1: expected} = condition,
         _events,
         _world,
         _source,
         target
       ) do
    metadata_comparison_result(condition, target, :loot_state, expected)
  end

  defp evaluate_condition(
         %Condition{type: :object_go_state, value1: expected} = condition,
         _events,
         _world,
         _source,
         target
       ) do
    metadata_comparison_result(condition, target, :go_state, expected)
  end

  defp evaluate_condition(
         %Condition{type: :object_fit_condition, value1: db_guid, children: [child]},
         events,
         world,
         source,
         _target
       ) do
    case Metadata.find_guid_by(:db_guid, db_guid) do
      guid when is_integer(guid) ->
        if match?({^world, _x, _y, _z}, World.position(guid)) do
          condition_result(child, events, world, source, guid)
        else
          :unmet
        end

      _missing ->
        :unmet
    end
  end

  defp evaluate_condition(
         %Condition{type: :distance_to_target, value1: expected, value2: comparison} = condition,
         _events,
         _world,
         source,
         target
       ) do
    source
    |> World.distance_between(target)
    |> trunc_distance()
    |> case do
      distance when is_integer(distance) -> Result.compare_result(distance, expected, comparison, condition)
      _missing -> Result.unknown(condition, {:missing_fact, :source_or_target, :position})
    end
  end

  defp evaluate_condition(%Condition{type: :line_of_sight} = condition, _events, world, source, target) do
    case {World.position(source), World.position(target)} do
      {{^world, x1, y1, z1}, {^world, x2, y2, z2}} ->
        Result.truth(Pathfinding.line_of_sight?(world.map_id, {x1, y1, z1}, {x2, y2, z2}))

      _missing ->
        Result.unknown(condition, {:missing_fact, :source_or_target, :position})
    end
  end

  defp evaluate_condition(
         %Condition{type: :distance_to_position, value1: x, value2: y, value3: z, value4: maximum} = condition,
         _events,
         world,
         _source,
         target
       ) do
    case World.position(target) do
      {^world, tx, ty, tz} -> Result.truth(Math.distance({tx, ty, tz}, {x, y, z}) <= maximum)
      _missing -> Result.unknown(condition, {:missing_fact, :target, :position})
    end
  end

  defp evaluate_condition(
         %Condition{type: :nearby_player, value1: mode, value2: radius} = condition,
         _events,
         world,
         _source,
         target
       ) do
    case World.position(target) do
      {^world, x, y, z} ->
        players = World.nearby_players_at(world, {x, y, z}, radius)
        nearby_player_result(condition, target, players, mode)

      _position ->
        Result.unknown(condition, {:missing_fact, :target, :position})
    end
  end

  defp evaluate_condition(%Condition{type: :source_entry} = condition, _events, _world, source, _target) do
    if is_integer(source) and source > 0 do
      Result.truth(Guid.entry(source) in [condition.value1, condition.value2, condition.value3, condition.value4])
    else
      Result.unknown(condition, {:missing_fact, :source, :entry})
    end
  end

  defp evaluate_condition(%Condition{type: :db_guid} = condition, _events, _world, source, _target) do
    if is_integer(source) and source > 0 do
      Result.truth(Guid.low_guid(source) in [condition.value1, condition.value2, condition.value3, condition.value4])
    else
      Result.unknown(condition, {:missing_fact, :source, :db_guid})
    end
  end

  defp evaluate_condition(%Condition{} = condition, _events, _world, _source, _target) do
    Result.unknown(condition, {:unsupported_capability, condition.type})
  end

  defp trunc_distance(distance) when is_number(distance), do: trunc(distance)
  defp trunc_distance(_distance), do: nil

  defp maybe_add_dead_result(results, false, _condition, _guid), do: results

  defp maybe_add_dead_result(results, true, condition, guid) do
    [condition |> alive_result(guid) |> Result.negate() | results]
  end

  defp maybe_add_distance_result(results, false, _condition, _world, _source, _target, _distance), do: results

  defp maybe_add_distance_result(results, true, condition, world, source, target, maximum) do
    result =
      case {World.position(source), World.position(target)} do
        {{^world, _sx, _sy, _sz}, {^world, _tx, _ty, _tz}} ->
          Result.truth(World.distance_between(source, target) > maximum)

        {{_source_world, _sx, _sy, _sz}, {_target_world, _tx, _ty, _tz}} ->
          :met

        _missing ->
          Result.unknown(condition, {:missing_fact, :source_or_target, :position})
      end

    [result | results]
  end

  defp alive_result(condition, guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: alive?} when is_boolean(alive?) -> Result.truth(alive?)
      _missing -> Result.unknown(condition, {:missing_fact, :target, :alive})
    end
  end

  defp nearby_creature_result(condition, {guid, _distance}, dead) do
    case alive_result(condition, guid) do
      :met -> Result.truth(dead == 0)
      :unmet -> Result.truth(dead != 0)
      {:unknown, _reasons} = unknown -> unknown
    end
  end

  defp event_target_condition_result(target, child, events, world, source) do
    if present?(target.guid), do: condition_result(child, events, world, source, target.guid), else: :met
  end

  defp reaction_available?(source, target) do
    match?(%{faction_template: %{}}, Metadata.query(source, [:faction_template])) and
      match?(%{faction_template: %{}}, Metadata.query(target, [:faction_template]))
  end

  defp metadata_result(condition, guid, key) do
    case Metadata.query(guid, [key]) do
      %{^key => value} when is_boolean(value) -> Result.truth(value)
      _missing -> Result.unknown(condition, {:missing_fact, :target, key})
    end
  end

  defp metadata_comparison_result(condition, guid, key, expected) do
    case Metadata.query(guid, [key]) do
      %{^key => value} when is_integer(value) -> Result.truth(value == expected)
      _missing -> Result.unknown(condition, {:missing_fact, :target, key})
    end
  end

  defp nearby_player_result(_condition, _target, players, 0), do: Result.truth(players != [])

  defp nearby_player_result(condition, target, players, mode) when mode in [1, 2] do
    players
    |> Enum.map(fn {guid, _distance} -> player_reaction_result(condition, target, guid, mode) end)
    |> Result.combine_or()
  end

  defp nearby_player_result(condition, _target, _players, mode) do
    Result.unknown(condition, {:invalid_mode, mode})
  end

  defp player_reaction_result(condition, target, player_guid, mode) do
    if reaction_available?(target, player_guid) do
      matches? =
        case mode do
          1 -> Hostility.hostile?(target, player_guid)
          2 -> Hostility.friendly?(target, player_guid)
        end

      Result.truth(matches?)
    else
      Result.unknown(condition, {:missing_fact, :nearby_player, :reaction})
    end
  end

  defp present?(guid), do: Metadata.get(guid) != nil

  defp send_event(%Event{} = event, data, target_mode) do
    main = [event.source_guid, event.target_guid]
    extra = Enum.map(event.targets, & &1.guid)

    recipients =
      case target_mode do
        0 -> main
        1 -> extra
        _mode -> main ++ extra
      end

    recipients
    |> Enum.uniq()
    |> Enum.filter(&(Guid.entity_type(&1) == :mob))
    |> Enum.each(&Entity.script_event(&1, event.id, data))
  end

  defp start_script_for_all(%Effects.ScriptedEventCommand{} = effect) do
    with {world, x, y, z} <- World.position(effect.source_guid) do
      effect.step.datalong2
      |> nearby_targets(world, x, y, z, effect.step.datalong4)
      |> Enum.filter(fn guid -> effect.step.datalong3 in [0, Guid.entry(guid)] end)
      |> Enum.each(&run_steps(&1, sub_steps(effect.step, effect.step.datalong), effect.target_guid))
    end
  end

  defp nearby_targets(0, world, x, y, z, radius),
    do: World.nearby_units_exact(:game_objects, world, {x, y, z}, radius) |> Enum.map(&elem(&1, 0))

  defp nearby_targets(1, world, x, y, z, radius),
    do: nearby_targets(2, world, x, y, z, radius) ++ nearby_targets(3, world, x, y, z, radius)

  defp nearby_targets(2, world, x, y, z, radius),
    do: World.nearby_units_exact(:mobs, world, {x, y, z}, radius) |> Enum.map(&elem(&1, 0))

  defp nearby_targets(3, world, x, y, z, radius),
    do: World.nearby_units_exact(:players, world, {x, y, z}, radius) |> Enum.map(&elem(&1, 0))

  defp nearby_targets(_type, _world, _x, _y, _z, _radius), do: []

  defp edit_condition(event, _field, value, _condition) when value < 0, do: event
  defp edit_condition(event, :success_condition, _value, condition), do: %{event | success_condition: condition}
  defp edit_condition(event, :failure_condition, _value, condition), do: %{event | failure_condition: condition}

  defp edit_steps(event, _field, value, _step) when value < 0, do: event
  defp edit_steps(event, :success_steps, value, step), do: %{event | success_steps: sub_steps(step, value)}
  defp edit_steps(event, :failure_steps, value, step), do: %{event | failure_steps: sub_steps(step, value)}

  defp sub_steps(%ScriptStep{sub_scripts: scripts}, id), do: Map.get(scripts, id, [])

  defp run_steps(_guid, [], _target_guid), do: :ok
  defp run_steps(guid, steps, target_guid), do: Entity.start_script(guid, steps, target_guid || 0)

  defp update_event(events, key, update) do
    case Map.get(events, key) do
      %Event{} = event -> Map.put(events, key, update.(event))
      nil -> events
    end
  end

  defp schedule(key, token), do: Process.send_after(self(), {:evaluate, key, token}, 1_000)
  defp event_key(world, id), do: {WorldRef.coerce(world), id}
  defp condition_key(%Condition{entry: entry}) when is_integer(entry) and entry > 0, do: entry
  defp condition_key(%Condition{} = condition), do: condition
end
