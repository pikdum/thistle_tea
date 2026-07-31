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
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
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

  @impl GenServer
  def init(state), do: {:ok, state}

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
    {source_guid, target_guid} =
      if condition.swap_targets?, do: {target_guid, source_guid}, else: {source_guid, target_guid}

    result = evaluate_condition(condition, events, world, source_guid, target_guid)
    if condition.reverse?, do: not result, else: result
  end

  defp evaluate_condition(%Condition{type: :none}, _events, _world, _source_guid, _target_guid), do: true

  defp evaluate_condition(%Condition{type: :not, children: [child]}, events, world, source_guid, target_guid),
    do: not condition_met?(child, events, world, source_guid, target_guid)

  defp evaluate_condition(%Condition{type: :or, children: children}, events, world, source_guid, target_guid),
    do: Enum.any?(children, &condition_met?(&1, events, world, source_guid, target_guid))

  defp evaluate_condition(%Condition{type: :and, children: children}, events, world, source_guid, target_guid),
    do: Enum.all?(children, &condition_met?(&1, events, world, source_guid, target_guid))

  defp evaluate_condition(%Condition{type: :escort, value1: flags, value2: distance}, _events, world, source, target) do
    source_dead? = (flags &&& 0x1) != 0 and not alive?(source)
    target_dead? = (flags &&& 0x2) != 0 and not alive?(target)
    too_far? = distance > 0 and not within?(world, source, target, distance)
    source_dead? or target_dead? or too_far?
  end

  defp evaluate_condition(
         %Condition{type: :map_event_data, value1: id, value2: index, value3: expected, value4: comparison},
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

    compare(value, expected, comparison)
  end

  defp evaluate_condition(%Condition{type: :map_event_active, value1: id}, events, world, _source, _target),
    do: Map.has_key?(events, event_key(world, id))

  defp evaluate_condition(
         %Condition{type: :map_event_targets, value1: id, children: [child]},
         events,
         world,
         source,
         _target
       ) do
    case Map.get(events, event_key(world, id)) do
      %Event{targets: targets} ->
        Enum.all?(targets, fn target ->
          not present?(target.guid) or condition_met?(child, events, world, source, target.guid)
        end)

      nil ->
        true
    end
  end

  defp evaluate_condition(%Condition{type: :alive}, _events, _world, _source, target), do: alive?(target)

  defp evaluate_condition(%Condition{type: :nearby_player, value2: radius}, _events, world, _source, target) do
    case World.position(target) do
      {^world, x, y, z} -> SpatialHash.query(:players, world, x, y, z, radius) != []
      _position -> false
    end
  end

  defp evaluate_condition(%Condition{type: :source_entry} = condition, _events, _world, source, _target) do
    entry = Guid.entry(source)
    entry in [condition.value1, condition.value2, condition.value3, condition.value4]
  end

  defp evaluate_condition(%Condition{type: :db_guid} = condition, _events, _world, source, _target) do
    guid = Guid.low_guid(source)
    guid in [condition.value1, condition.value2, condition.value3, condition.value4]
  end

  defp evaluate_condition(%Condition{}, _events, _world, _source, _target), do: false

  defp compare(nil, _expected, _comparison), do: false
  defp compare(value, expected, 1), do: value >= expected
  defp compare(value, expected, 2), do: value <= expected
  defp compare(value, expected, _comparison), do: value == expected

  defp alive?(guid) when is_integer(guid) and guid > 0 do
    match?(%{alive?: true}, Metadata.query(guid, [:alive?]))
  end

  defp alive?(_guid), do: false
  defp present?(guid), do: Metadata.get(guid) != nil

  defp within?(world, source_guid, target_guid, distance) do
    case {World.position(source_guid), World.position(target_guid)} do
      {{^world, x1, y1, z1}, {^world, x2, y2, z2}} ->
        SpatialHash.distance({x1, y1, z1}, {x2, y2, z2}) <= distance

      _positions ->
        false
    end
  end

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
    do: SpatialHash.query(:game_objects, world, x, y, z, radius) |> Enum.map(&elem(&1, 0))

  defp nearby_targets(1, world, x, y, z, radius),
    do: nearby_targets(2, world, x, y, z, radius) ++ nearby_targets(3, world, x, y, z, radius)

  defp nearby_targets(2, world, x, y, z, radius),
    do: SpatialHash.query(:mobs, world, x, y, z, radius) |> Enum.map(&elem(&1, 0))

  defp nearby_targets(3, world, x, y, z, radius),
    do: SpatialHash.query(:players, world, x, y, z, radius) |> Enum.map(&elem(&1, 0))

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
end
