defmodule ThistleTea.Game.Core.InstanceScript.BlackrockSpire do
  @moduledoc """
  The doors and events of Blackrock Spire, after vmangos
  `instance_blackrock_spire`.

  The Dragonspine Door into Upper Blackrock Spire opens for a party that
  carries the Seal of Ascension: stepping up to it (`AreaTriggerScript`)
  lights its six braziers two by two and swings it open. Past it, each of the
  seven alcoves of the Hall of Blackhand has a dark iron rune that goes dark
  once the Blackhand summoners and veterans guarding it are dead, and when
  every rune is dark the way to Pyroguard Emberseer opens. The Emberseer fight
  itself runs from its database event, which records his defeat here, and the
  door out of his hall stays open after that. General Drakkisath's EventAI
  records his fight, and his death opens the gates behind him.

  Opening Father Flame while Drakkisath lives starts the rookery: a pair of
  Rookery Hatchers arrives, then four more pairs of hatchers and guardians
  every thirty to forty seconds, and finally Solakar Flamewreath himself.

  vmangos sorts the summoners and veterans standing within ten yards of each
  rune when the event starts; here those guardians are the fixed spawns the
  database places there, so a guardian pulled away still counts for its
  alcove. The rookery's middle waves come in a fixed order where vmangos rolls
  each one.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @room_event_field 0
  @emberseer_field 1
  @flamewreath_field 2
  @stadium_field 3
  @valthalak_field 4
  @ubrs_door_field 5
  @solakar_field 6
  @drakkisath_field 7

  @in_progress 1
  @done 3

  @emberseer_in 175_244
  @emberseer_out 175_153
  @dragonspine_door 164_725
  @braziers [{175_528, 175_529}, {175_530, 175_531}, {175_532, 175_533}]
  @drakkisath_gates [175_946, 175_947]
  @father_flame 175_245

  @rooms %{
    175_197 => [40_259, 40_260],
    175_199 => [40_254, 40_255, 45_834],
    175_195 => [40_251],
    175_200 => [40_262, 40_263],
    175_198 => [40_267, 40_268, 45_833],
    175_196 => [40_270, 45_832],
    175_194 => [40_277, 40_455]
  }

  @door_first_ms 2_000
  @door_step_ms 3_000

  @rookery_hatcher 10_683
  @rookery_guardian 10_258
  @solakar 10_264
  @say_rookery_start 5_538
  @rookery_spots [{55.232342, -265.751282, 93.883, 5.0}, {60.011333, -263.914703, 94.022, 5.0}]
  @solakar_spot {43.7685, -259.82, 91.6483, 0.0}
  @rookery_waves [
    [@rookery_hatcher, @rookery_hatcher],
    [@rookery_guardian, @rookery_hatcher],
    [@rookery_guardian, @rookery_guardian],
    [@rookery_hatcher, @rookery_hatcher],
    [@rookery_guardian, @rookery_hatcher]
  ]
  @first_wave_ms 5_000
  @wave_min_ms 30_000
  @wave_max_ms 40_000
  @summon_lifetime_ms 3_600_000
  @dead_despawn 7

  def broadcast_text_ids, do: [@say_rookery_start]
  def summon_entries, do: [@rookery_hatcher, @rookery_guardian, @solakar]
  def game_object_db_guids, do: []

  def registered_fields,
    do: [
      @room_event_field,
      @emberseer_field,
      @flamewreath_field,
      @stadium_field,
      @valthalak_field,
      @ubrs_door_field,
      @solakar_field,
      @drakkisath_field
    ]

  def door_entries, do: [@emberseer_in, @emberseer_out, @dragonspine_door | @drakkisath_gates] ++ Map.keys(@rooms)

  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, field, value) do
    previous = Encounter.value(data, field)
    stored = Encounter.settle(data, field, value)
    data = Map.put(data, field, stored)
    effects = if stored == previous, do: [], else: changed(field, stored)
    {:ok, stored, data, effects}
  end

  def game_object_used(data, script_state, @father_flame) do
    if Encounter.value(data, @solakar_field) in [0, 2] and not Encounter.done?(data, @drakkisath_field) do
      {:ok, _stored, data, effects} = set_data(data, @solakar_field, @in_progress)
      {:ok, data, Map.put(script_state, :rookery_wave, 0), effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(_data, script_state, entry) when is_map_key(@rooms, entry) do
    if room_clear?(script_state, entry), do: {:ok, [operate(entry, :close)]}, else: {:ok, []}
  end

  def game_object_spawned(data, _script_state, entry) do
    {:ok, for({field, entries} <- doors(), Encounter.done?(data, field), entry in entries, do: operate(entry, :open))}
  end

  def creature_event(data, script_state, %{event: :death, db_guid: db_guid}) when is_integer(db_guid) do
    case Enum.find(@rooms, fn {_rune, guards} -> db_guid in guards end) do
      nil -> {:ok, data, script_state, []}
      {rune, _guards} -> guard_slain(data, script_state, rune, db_guid)
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, {:ubrs_door, step}) when step <= length(@braziers) do
    {left, right} = Enum.at(@braziers, step - 1)
    next = %Effects.Schedule{key: {:ubrs_door, step + 1}, delay_ms: @door_step_ms}
    {:ok, data, script_state, [operate(left, :open), operate(right, :open), next]}
  end

  def timer(data, script_state, {:ubrs_door, _step}), do: {:ok, data, script_state, [operate(@dragonspine_door, :open)]}

  def timer(data, script_state, :rookery_wave) do
    wave = Map.get(script_state, :rookery_wave, 0)

    cond do
      Encounter.value(data, @solakar_field) != @in_progress ->
        {:ok, data, script_state, []}

      wave < length(@rookery_waves) ->
        summons = rookery_wave(wave)
        next = %Effects.Schedule{key: :rookery_wave, delay_ms: @wave_min_ms, max_delay_ms: @wave_max_ms}
        {:ok, data, Map.put(script_state, :rookery_wave, wave + 1), summons ++ [next]}

      true ->
        {:ok, _stored, data, effects} = set_data(data, @solakar_field, @done)
        {:ok, data, script_state, [summon(@solakar, @solakar_spot, []) | effects]}
    end
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp changed(@room_event_field, @done), do: [operate(@emberseer_in, :open)]
  defp changed(@ubrs_door_field, @done), do: [%Effects.Schedule{key: {:ubrs_door, 1}, delay_ms: @door_first_ms}]
  defp changed(@drakkisath_field, @done), do: Enum.map(@drakkisath_gates, &operate(&1, :open))
  defp changed(@solakar_field, @in_progress), do: [%Effects.Schedule{key: :rookery_wave, delay_ms: @first_wave_ms}]
  defp changed(_field, _value), do: []

  defp guard_slain(data, script_state, rune, db_guid) do
    script_state = Map.update(script_state, :slain, MapSet.new([db_guid]), &MapSet.put(&1, db_guid))

    if room_clear?(script_state, rune) do
      dark = [operate(rune, :close)]

      if Enum.all?(Map.keys(@rooms), &room_clear?(script_state, &1)) do
        {:ok, _stored, data, effects} = set_data(data, @room_event_field, @done)
        {:ok, data, script_state, dark ++ effects}
      else
        {:ok, data, script_state, dark}
      end
    else
      {:ok, data, script_state, []}
    end
  end

  defp room_clear?(script_state, rune) do
    slain = Map.get(script_state, :slain, MapSet.new())
    @rooms |> Map.fetch!(rune) |> Enum.all?(&MapSet.member?(slain, &1))
  end

  defp rookery_wave(wave) do
    talk = if wave == 0, do: [%ScriptStep{command: :talk, dataint: @say_rookery_start}], else: []

    @rookery_waves
    |> Enum.at(wave)
    |> Enum.zip(@rookery_spots)
    |> Enum.with_index()
    |> Enum.map(fn {{entry, spot}, index} -> summon(entry, spot, if(index == 0, do: talk, else: [])) end)
  end

  defp doors do
    [
      {@room_event_field, [@emberseer_in]},
      {@emberseer_field, [@emberseer_out]},
      {@ubrs_door_field, [@dragonspine_door | Enum.flat_map(@braziers, &Tuple.to_list/1)]},
      {@drakkisath_field, @drakkisath_gates}
    ]
  end

  defp summon(entry, position, steps) do
    %Effects.SummonCreature{
      entry: entry,
      position: position,
      despawn_delay_ms: @summon_lifetime_ms,
      despawn_type: @dead_despawn,
      steps: steps
    }
  end

  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}
end
