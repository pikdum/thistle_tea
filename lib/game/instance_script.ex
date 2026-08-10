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

  def timer(script_name, data, script_state, key) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.timer(data, script_state, key)
    end
  end

  defp adapter("instance_stratholme"), do: Stratholme
  defp adapter(_script_name), do: nil
end

defmodule ThistleTea.Game.InstanceScript.Stratholme do
  @moduledoc false

  alias ThistleTea.Game.InstanceScript.Effects

  @baron_run 0
  @baroness 1
  @nerub 2
  @pallid 3
  @ramstein 4
  @baron 5
  @crystal_all_die 6
  @aurius_event 7
  @ramstein_event 8

  @not_started 0
  @in_progress 1
  @fail 2
  @done 3
  @special 4

  @baroness_entry 10_436
  @nerub_entry 10_437
  @pallid_entry 10_438
  @ramstein_entry 10_439
  @baron_entry 10_440
  @crystal_entry 10_415
  @acolyte_entry 10_399
  @bile_spewer_entry 10_416
  @venom_belcher_entry 10_417
  @black_guard_entry 10_394
  @mindless_undead_entry 11_030
  @ysida_entry 16_031

  @ziggurat_doors %{@baroness => 175_380, @nerub => 175_379, @pallid => 175_381}
  @ziggurat_four 175_405
  @ziggurat_five 175_796
  @port_gauntlet 175_374
  @port_slaughter 175_373
  @slaughter_square_gate 175_358
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

  @acolyte_groups %{
    53_955 => [53_268, 53_269, 53_270, 53_271, 53_272],
    53_963 => [53_257, 53_258, 53_259, 53_260, 53_261],
    53_968 => [53_262, 53_263, 53_264, 53_265, 53_266]
  }
  @crystal_db_guids Map.keys(@acolyte_groups)
  @abomination_db_guids [
    53_969,
    54_002,
    54_018,
    54_019,
    54_020,
    54_021,
    54_022,
    54_026,
    54_027,
    54_039,
    54_040,
    54_041,
    54_050
  ]
  @baron_locked_flags 0x02000002

  def broadcast_text_ids,
    do: [6_289, 6_398, 6_401, 6_415, 6_425, 6_527, 11_812, 11_813, 11_814, 11_815, 11_816, 11_817, 11_931]

  def summon_entries, do: [@black_guard_entry, @ramstein_entry, @mindless_undead_entry, @ysida_entry]

  def registered_fields,
    do: [@baron_run, @baroness, @nerub, @pallid, @ramstein, @baron, @crystal_all_die, @aurius_event, @ramstein_event]

  def initial_value(field) when field in 0..8, do: @not_started

  def set_data(data, @baron_run, value), do: set_baron_run(data, value)

  def set_data(data, field, value) when field in [@baroness, @nerub, @pallid] do
    effects = if value == @done, do: [operate(Map.fetch!(@ziggurat_doors, field), :open)], else: []
    {:ok, value, Map.put(data, field, value), effects}
  end

  def set_data(data, @ramstein, value), do: set_ramstein(data, value)

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
  def set_data(data, @crystal_all_die, value), do: {:ok, value, Map.put(data, @crystal_all_die, value), []}
  def set_data(data, @ramstein_event, value), do: {:ok, value, Map.put(data, @ramstein_event, value), []}

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

  def creature_event(data, script_state, event) do
    handle_creature_event(data, ensure_script_state(script_state), event)
  end

  defp handle_creature_event(data, script_state, %{creature_entry: @baron_entry, event: :spawned}) do
    if Map.get(data, @ramstein, @not_started) == @done do
      {:ok, data, script_state, []}
    else
      effect = %Effects.ModifyCreatureUnitFlags{creature_entry: @baron_entry, flags: @baron_locked_flags, mode: :add}
      {:ok, data, script_state, [effect]}
    end
  end

  defp handle_creature_event(data, script_state, %{creature_entry: entry, event: :death})
       when entry in [@baroness_entry, @nerub_entry, @pallid_entry] do
    field = boss_field(entry)
    {:ok, _stored, data, effects} = set_data(data, field, @done)
    {:ok, data, script_state, effects}
  end

  defp handle_creature_event(data, script_state, %{creature_entry: @acolyte_entry, event: :death, db_guid: db_guid})
       when is_integer(db_guid) do
    {new_death?, script_state} = remember(script_state, :dead_acolytes, db_guid)

    case new_death? && completed_acolyte_crystal(script_state, db_guid) do
      crystal_db_guid when is_integer(crystal_db_guid) ->
        {new_crystal?, script_state} = remember(script_state, :triggered_crystals, crystal_db_guid)
        effects = if new_crystal?, do: [kill_crystal(crystal_db_guid)], else: []
        {:ok, data, script_state, effects}

      _incomplete ->
        {:ok, data, script_state, []}
    end
  end

  defp handle_creature_event(data, script_state, %{
         creature_entry: @crystal_entry,
         creature_guid: creature_guid,
         event: :death,
         db_guid: db_guid
       })
       when is_integer(db_guid) do
    {new_death?, script_state} = remember(script_state, :dead_crystals, db_guid)

    cond do
      not new_death? ->
        {:ok, data, script_state, []}

      all_crystals_dead?(script_state) ->
        data = Map.put(data, @crystal_all_die, @done)

        effects = [
          talk(@crystal_entry, 6_527, creature_guid),
          operate(@port_gauntlet, :open),
          operate(@port_slaughter, :open),
          talk(@crystal_entry, 6_289, creature_guid)
        ]

        {:ok, data, script_state, effects}

      true ->
        {:ok, data, script_state, [talk(@crystal_entry, 6_527, creature_guid)]}
    end
  end

  defp handle_creature_event(data, script_state, %{creature_entry: entry, event: :spawned} = event)
       when entry in [@bile_spewer_entry, @venom_belcher_entry] do
    queue = [{event.creature_guid, entry} | script_state.abomination_queue] |> Enum.uniq() |> Enum.sort()
    {:ok, data, %{script_state | abomination_queue: queue}, []}
  end

  defp handle_creature_event(data, script_state, %{creature_entry: entry, event: :death, db_guid: db_guid} = event)
       when entry in [@bile_spewer_entry, @venom_belcher_entry] do
    identity = if is_integer(db_guid), do: db_guid, else: event.creature_guid
    {new_death?, script_state} = remember(script_state, :dead_abominations, identity)

    script_state = %{
      script_state
      | abomination_queue: List.keydelete(script_state.abomination_queue, event.creature_guid, 0)
    }

    cond do
      not new_death? ->
        {:ok, data, script_state, []}

      all_abominations_dead?(script_state) and not script_state.ramstein_summoned? ->
        data = data |> Map.put(@ramstein, @in_progress) |> Map.put(@ramstein_event, @done)
        script_state = %{script_state | ramstein_summoned?: true}

        effects = [
          talk(@baron_entry, 6_398),
          operate(@ziggurat_four, :open),
          summon(
            @ramstein_entry,
            {4_032.35, -3_380.567, 119.739571, 4.7614},
            {4_033.009, -3_404.3293, 115.3554}
          ),
          schedule(:ramstein_arrival, 5_000)
        ]

        {:ok, data, script_state, effects}

      true ->
        {:ok, Map.put(data, @ramstein, @in_progress), script_state, []}
    end
  end

  defp handle_creature_event(data, script_state, %{creature_entry: @ramstein_entry, event: :aggro}) do
    data = Map.put(data, @ramstein, @in_progress)
    {:ok, data, script_state, [operate(@port_gauntlet, :close)]}
  end

  defp handle_creature_event(data, script_state, %{creature_entry: @ramstein_entry, event: :evade}) do
    with_script_state(set_ramstein(data, @fail), script_state)
  end

  defp handle_creature_event(data, script_state, %{creature_entry: @ramstein_entry, event: :death}) do
    if script_state.ramstein_dead? do
      {:ok, data, script_state, []}
    else
      script_state = %{script_state | ramstein_dead?: true}
      with_script_state(set_ramstein(data, @done), script_state)
    end
  end

  defp handle_creature_event(data, %{black_guards_announced?: false} = script_state, %{
         creature_entry: @black_guard_entry,
         creature_guid: creature_guid,
         event: :spawned
       }) do
    script_state = %{script_state | black_guards_announced?: true}
    {:ok, data, script_state, [talk(@black_guard_entry, 6_415, creature_guid)]}
  end

  defp handle_creature_event(data, script_state, %{
         creature_entry: @black_guard_entry,
         creature_guid: creature_guid,
         event: :death
       }) do
    {new_death?, script_state} = remember(script_state, :dead_black_guards, creature_guid)

    effects =
      if new_death? and MapSet.size(script_state.dead_black_guards) == 5 do
        [talk(@baron_entry, 6_401)]
      else
        []
      end

    {:ok, data, script_state, effects}
  end

  defp handle_creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, :baron_run_10_minutes),
    do: with_script_state(baron_run_timer(data, [talk(@baron_entry, 11_813), cast_player_spell(27_863)]), script_state)

  def timer(data, script_state, :baron_run_5_minutes),
    do: with_script_state(baron_run_timer(data, [talk(@baron_entry, 11_815), cast_player_spell(27_864)]), script_state)

  def timer(data, script_state, :baron_run_ysida),
    do: with_script_state(baron_run_timer(data, [talk(@ysida_entry, 11_816)]), script_state)

  def timer(data, script_state, :baron_run_1_minute),
    do: with_script_state(baron_run_timer(data, [cast_player_spell(27_865)]), script_state)

  def timer(data, script_state, :baron_run_expired) do
    result =
      case Map.get(data, @baron_run, @not_started) do
        @in_progress -> {:ok, Map.put(data, @baron_run, @fail), baron_run_failed_effects()}
        _finished -> {:ok, data, []}
      end

    with_script_state(result, script_state)
  end

  def timer(data, script_state, :ysida_reward) do
    result =
      if Map.get(data, @baron_run, @not_started) == @done do
        {:ok, data, [talk(@ysida_entry, 11_931)]}
      else
        {:ok, data, []}
      end

    with_script_state(result, script_state)
  end

  def timer(data, script_state, :abomination_wave) do
    script_state = ensure_script_state(script_state)

    case script_state.abomination_queue do
      [{creature_guid, entry} | remaining] ->
        delay_ms = if entry == @bile_spewer_entry, do: 45_000, else: 37_500
        script_state = %{script_state | abomination_queue: remaining}

        effects = [
          %Effects.MoveCreature{
            creature_entry: entry,
            creature_guid: creature_guid,
            position: {4_037.194, -3_473.741943, 121.738808}
          }
          | if(remaining == [], do: [], else: [schedule(:abomination_wave, delay_ms)])
        ]

        {:ok, data, script_state, effects}

      [] ->
        {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, :ramstein_arrival) do
    {:ok, data, script_state, [operate(@ziggurat_four, :close), talk(@ramstein_entry, 6_425)]}
  end

  def timer(data, script_state, :black_guard_assault) do
    effects =
      black_guard_summons() ++
        [
          operate(@ziggurat_four, :open),
          operate(@ziggurat_five, :open),
          %Effects.ModifyCreatureUnitFlags{
            creature_entry: @baron_entry,
            flags: @baron_locked_flags,
            mode: :remove
          }
        ]

    {:ok, data, script_state, effects}
  end

  def timer(data, script_state, :slaughter_square_gate_reset) do
    {:ok, data, script_state, [operate(@slaughter_square_gate, :close)]}
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

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

  defp set_ramstein(data, @special) do
    effects = [operate(@port_gauntlet, :close), schedule(:abomination_wave, 20_000)]
    {:ok, @special, Map.put(data, @ramstein, @special), effects}
  end

  defp set_ramstein(data, @fail) do
    effects = [operate(@port_gauntlet, :open), %Effects.CancelSchedules{keys: [:abomination_wave]}]
    {:ok, @fail, Map.put(data, @ramstein, @fail), effects}
  end

  defp set_ramstein(data, @done) do
    effects =
      [operate(@slaughter_square_gate, :open)] ++
        mindless_undead_summons() ++
        [schedule(:black_guard_assault, 60_000), schedule(:slaughter_square_gate_reset, 91_000)]

    {:ok, @done, Map.put(data, @ramstein, @done), effects}
  end

  defp set_ramstein(data, value), do: {:ok, value, Map.put(data, @ramstein, value), []}

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

  defp talk(creature_entry, broadcast_text_id, creature_guid \\ nil) do
    %Effects.MonsterTalk{
      creature_entry: creature_entry,
      broadcast_text_id: broadcast_text_id,
      creature_guid: creature_guid
    }
  end

  defp cast_player_spell(spell_id), do: %Effects.CastPlayerSpell{spell_id: spell_id}
  defp schedule(key, delay_ms), do: %Effects.Schedule{key: key, delay_ms: delay_ms}

  defp with_script_state({:ok, data, effects}, script_state), do: {:ok, data, script_state, effects}
  defp with_script_state({:ok, _stored, data, effects}, script_state), do: {:ok, data, script_state, effects}

  defp ensure_script_state(script_state) do
    Map.merge(
      %{
        dead_acolytes: MapSet.new(),
        triggered_crystals: MapSet.new(),
        dead_crystals: MapSet.new(),
        dead_abominations: MapSet.new(),
        abomination_queue: [],
        ramstein_summoned?: false,
        ramstein_dead?: false,
        black_guards_announced?: false,
        dead_black_guards: MapSet.new()
      },
      script_state
    )
  end

  defp remember(script_state, key, identity) do
    seen = Map.fetch!(script_state, key)
    {not MapSet.member?(seen, identity), Map.put(script_state, key, MapSet.put(seen, identity))}
  end

  defp completed_acolyte_crystal(script_state, db_guid) do
    Enum.find_value(@acolyte_groups, fn {crystal_db_guid, acolyte_guids} ->
      if db_guid in acolyte_guids and Enum.all?(acolyte_guids, &MapSet.member?(script_state.dead_acolytes, &1)) do
        crystal_db_guid
      end
    end)
  end

  defp all_crystals_dead?(script_state) do
    Enum.all?(@crystal_db_guids, &MapSet.member?(script_state.dead_crystals, &1))
  end

  defp all_abominations_dead?(script_state) do
    Enum.all?(@abomination_db_guids, &MapSet.member?(script_state.dead_abominations, &1))
  end

  defp boss_field(@baroness_entry), do: @baroness
  defp boss_field(@nerub_entry), do: @nerub
  defp boss_field(@pallid_entry), do: @pallid

  defp kill_crystal(db_guid) do
    %Effects.TriggerCreatureSpell{
      creature_entry: @crystal_entry,
      creature_db_guid: db_guid,
      spell_id: 5
    }
  end

  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}

  defp summon(entry, position, move_to, despawn_delay_ms \\ 1_800_000) do
    %Effects.SummonCreature{
      entry: entry,
      position: position,
      move_to: move_to,
      despawn_delay_ms: despawn_delay_ms
    }
  end

  defp mindless_undead_summons do
    Enum.map(0..33, fn index ->
      x_offset = rem(index, 6) * 0.5
      y_offset = div(index, 6) * 0.5

      summon(
        @mindless_undead_entry,
        {3_929.6 + x_offset, -3_384.3 + y_offset, 120.0, 4.88},
        {3_941.29, -3_394.84, 119.69}
      )
    end)
  end

  defp black_guard_summons do
    Enum.map(0..4, fn index ->
      summon(
        @black_guard_entry,
        {4_032.84 + rem(index, 3), -3_380.567 + div(index, 3), 119.739571, 4.7614},
        {4_033.34, -3_419.75, 116.35}
      )
    end)
  end
end
