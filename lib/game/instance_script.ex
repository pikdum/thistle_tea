defmodule ThistleTea.Game.InstanceScript do
  @moduledoc """
  Registry for audited instance-script data adapters.
  """

  alias ThistleTea.Game.InstanceScript.Stratholme

  @adapters [Stratholme]

  def broadcast_text_ids do
    @adapters |> Enum.flat_map(& &1.broadcast_text_ids()) |> Enum.uniq()
  end

  def summon_entries do
    @adapters |> Enum.flat_map(& &1.summon_entries()) |> Enum.uniq()
  end

  def registered_fields(script_name) do
    case adapter(script_name) do
      nil -> []
      adapter -> adapter.registered_fields()
    end
  end

  def initial_value(script_name, field) do
    with adapter when not is_nil(adapter) <- adapter(script_name),
         true <- field in adapter.registered_fields() do
      {:ok, adapter.initial_value(field)}
    else
      nil -> {:error, {:unsupported_script, script_name}}
      false -> {:error, {:unsupported_field, field}}
    end
  end

  def set_data(script_name, data, field, value) do
    with adapter when not is_nil(adapter) <- adapter(script_name),
         true <- field in adapter.registered_fields() do
      adapter.set_data(data, field, value)
    else
      nil -> {:error, {:unsupported_script, script_name}}
      false -> {:error, {:unsupported_field, field}}
    end
  end

  def game_object_used(script_name, data, entry) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.game_object_used(data, entry)
    end
  end

  def creature_event(script_name, data, script_state, event) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.creature_event(data, script_state, event)
    end
  end

  def timer(script_name, data, key) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.timer(data, key)
    end
  end

  defp adapter("instance_stratholme"), do: Stratholme
  defp adapter(_script_name), do: nil
end

defmodule ThistleTea.Game.InstanceScript.Stratholme do
  @moduledoc false

  alias ThistleTea.Game.InstanceScript.Effects

  @baron_run 0
  @baron 5
  @aurius_event 7

  @not_started 0
  @in_progress 1
  @fail 2
  @done 3

  @baron_entry 10_440
  @ysida_entry 16_031

  @baron_gate_entries [175_405, 175_796, 175_374]
  @gauntlet_gate_entry 175_357
  @ysida_cage_entry 181_071

  @baron_run_schedules [
    :baron_run_10_minutes,
    :baron_run_5_minutes,
    :baron_run_ysida,
    :baron_run_1_minute,
    :baron_run_expired
  ]
  @baron_ultimatum_spells [27_861, 27_863, 27_864, 27_865]

  def broadcast_text_ids, do: [11_812, 11_813, 11_814, 11_815, 11_816, 11_817, 11_931]
  def summon_entries, do: [@ysida_entry]

  def registered_fields, do: [@baron_run, @baron, @aurius_event]

  def initial_value(field) when field in [@baron_run, @baron, @aurius_event], do: @not_started

  def set_data(data, @baron_run, value), do: set_baron_run(data, value)

  def set_data(data, @baron, value) do
    data = Map.put(data, @baron, value)
    door_effects = operate_baron_gates(if(value == @in_progress, do: :close, else: :open))

    case {value, Map.get(data, @baron_run, @not_started)} do
      {@done, @in_progress} ->
        {:ok, value, Map.put(data, @baron_run, @done), door_effects ++ baron_run_done_effects()}

      {state, _baron_run} when state in [@in_progress, @fail, @done] ->
        {:ok, value, data, door_effects}

      {_state, _baron_run} ->
        {:ok, value, data, []}
    end
  end

  def set_data(data, @aurius_event, value), do: {:ok, value, Map.put(data, @aurius_event, value), []}

  def game_object_used(data, @gauntlet_gate_entry) do
    case Map.get(data, @baron_run, @not_started) do
      @not_started ->
        {:ok, _stored, data, effects} = set_baron_run(data, @in_progress)
        {:ok, data, effects}

      _started ->
        {:ok, data, []}
    end
  end

  def game_object_used(data, _entry), do: {:ok, data, []}

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, :baron_run_10_minutes),
    do: baron_run_timer(data, [talk(@baron_entry, 11_813), cast_player_spell(27_863)])

  def timer(data, :baron_run_5_minutes),
    do: baron_run_timer(data, [talk(@baron_entry, 11_815), cast_player_spell(27_864)])

  def timer(data, :baron_run_ysida), do: baron_run_timer(data, [talk(@ysida_entry, 11_816)])
  def timer(data, :baron_run_1_minute), do: baron_run_timer(data, [cast_player_spell(27_865)])

  def timer(data, :baron_run_expired) do
    case Map.get(data, @baron_run, @not_started) do
      @in_progress -> {:ok, Map.put(data, @baron_run, @fail), baron_run_failed_effects()}
      _finished -> {:ok, data, []}
    end
  end

  def timer(data, :ysida_reward) do
    if Map.get(data, @baron_run, @not_started) == @done do
      {:ok, data, [talk(@ysida_entry, 11_931)]}
    else
      {:ok, data, []}
    end
  end

  def timer(data, _key), do: {:ok, data, []}

  defp set_baron_run(data, @in_progress) do
    data = Map.put(data, @baron_run, @in_progress)

    effects = [
      %Effects.SummonCreature{
        entry: @ysida_entry,
        position: {4_044.163, -3_334.2, 115.0596, 4.2},
        despawn_delay_ms: 3_600_000
      },
      talk(@baron_entry, 11_812),
      cast_player_spell(27_861),
      schedule(:baron_run_10_minutes, 35 * 60 * 1_000),
      schedule(:baron_run_5_minutes, 40 * 60 * 1_000),
      schedule(:baron_run_ysida, 40 * 60 * 1_000 + 3_000),
      schedule(:baron_run_1_minute, 44 * 60 * 1_000),
      schedule(:baron_run_expired, 45 * 60 * 1_000)
    ]

    {:ok, @in_progress, data, effects}
  end

  defp set_baron_run(data, @done) do
    {:ok, @done, Map.put(data, @baron_run, @done), baron_run_done_effects()}
  end

  defp set_baron_run(data, @fail) do
    {:ok, @fail, Map.put(data, @baron_run, @fail), baron_run_failed_effects()}
  end

  defp set_baron_run(data, value), do: {:ok, value, Map.put(data, @baron_run, value), []}

  defp baron_run_timer(data, effects) do
    if Map.get(data, @baron_run, @not_started) == @in_progress do
      {:ok, data, effects}
    else
      {:ok, data, []}
    end
  end

  defp baron_run_done_effects do
    [
      %Effects.CancelSchedules{keys: @baron_run_schedules},
      %Effects.RemovePlayerAuras{spell_ids: @baron_ultimatum_spells},
      %Effects.QuestKillCredit{creature_entry: @ysida_entry},
      %Effects.OperateGameObject{entry: @ysida_cage_entry, action: :open},
      %Effects.ModifyCreatureNpcFlags{creature_entry: @ysida_entry, flags: 0x3, mode: :add},
      %Effects.MoveCreature{creature_entry: @ysida_entry, position: {4_041.2, -3_339.0, 115.1}},
      schedule(:ysida_reward, 5_000)
    ]
  end

  defp baron_run_failed_effects do
    [
      %Effects.CancelSchedules{keys: @baron_run_schedules},
      talk(@baron_entry, 11_814),
      %Effects.OperateGameObject{entry: @ysida_cage_entry, action: :open},
      talk(@ysida_entry, 11_817),
      %Effects.TriggerCreatureSpell{creature_entry: @ysida_entry, spell_id: 5}
    ]
  end

  defp operate_baron_gates(action) do
    Enum.map(@baron_gate_entries, &%Effects.OperateGameObject{entry: &1, action: action})
  end

  defp talk(creature_entry, broadcast_text_id) do
    %Effects.MonsterTalk{creature_entry: creature_entry, broadcast_text_id: broadcast_text_id}
  end

  defp cast_player_spell(spell_id), do: %Effects.CastPlayerSpell{spell_id: spell_id}
  defp schedule(key, delay_ms), do: %Effects.Schedule{key: key, delay_ms: delay_ms}
end
