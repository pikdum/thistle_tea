defmodule ThistleTea.Game.Core.InstanceScript.ZulFarrak do
  @moduledoc """
  The pyramid event and the end door of Zul'Farrak, after vmangos
  `instance_zulfarrak`.

  Opening any troll cage frees Sergeant Bly's crew. They take the top of the
  pyramid stairs as their new home and turn on the trolls. When Weegli
  Blastfuse reaches the top (`CreatureScript.ZulFarrak`), the first wave
  gathers at the foot of the pyramid. Every ten seconds a larger group of it
  runs up the stairs, two trolls at first, then three, and so on. Ten seconds
  after the last of a wave falls, the second wave comes the same way. The
  third wave, with Shadowpriest Sezz'ziz and Nekrum Gutchewer, waits below, so
  the crew walks down to the foot of the stairs to meet it. Once it is dead
  too, the crew settles on the pyramid floor. There Weegli can blow the end
  door, and Chief Ukorz Sandscalp answers the blast.

  vmangos sends each troll to a random spot along the top of the stairs. Here
  the spots are spread evenly instead, which keeps the script deterministic.
  A wave counts as cleared only once every troll summoned for it has reported
  in and died.

  Zum'rah, Antu'sul, and Gahz'rilla are not part of this port.
  """

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @pyramid 1
  @gahzrilla 2
  @end_door 3
  @zumrah 4
  @antusul 5

  @not_started 0
  @cages_open 1
  @arrived_at_stair 2
  @wave_1 3
  @pre_wave_2 4
  @wave_2 5
  @pre_wave_3 6
  @wave_3 7
  @killed_all_trolls 8
  @done 3

  @bly 7_604
  @raven 7_605
  @oro 7_606
  @weegli 7_607
  @murta 7_608
  @ukorz 7_267
  @cages [141_070, 141_071, 141_072, 141_073, 141_074]
  @end_door_entry 146_084
  @ukorz_yell 6_067

  @freed 250
  @pathfind 0x1
  @walk 0x2
  @run 0x4
  @inform 0x2
  @at_stair 1
  @manual_despawn 8
  @floor_z 8.87
  @first_group_ms 1_000
  @group_interval_ms 10_000
  @wave_2_delay_ms 10_000
  @wave_3_delay_ms 5_000
  @first_group 2

  @waves %{
    1 => [
      {7_789, 1_894.64, 1_206.29},
      {7_787, 1_890.08, 1_218.68},
      {8_876, 1_883.76, 1_222.3},
      {7_789, 1_874.18, 1_221.24},
      {7_787, 1_892.28, 1_225.49},
      {7_788, 1_889.94, 1_212.21},
      {7_787, 1_879.02, 1_223.06},
      {7_789, 1_874.45, 1_204.44},
      {8_876, 1_898.23, 1_217.97},
      {7_787, 1_882.07, 1_225.7},
      {8_877, 1_896.46, 1_205.62},
      {7_787, 1_886.97, 1_225.86},
      {7_787, 1_894.72, 1_221.91},
      {7_787, 1_883.5, 1_218.25},
      {7_787, 1_886.93, 1_221.4},
      {8_876, 1_889.82, 1_222.51},
      {7_788, 1_893.07, 1_215.26},
      {7_788, 1_878.57, 1_214.16},
      {7_788, 1_883.74, 1_212.35},
      {8_877, 1_877.0, 1_207.27},
      {8_877, 1_873.63, 1_204.65},
      {8_876, 1_877.4, 1_216.41},
      {8_877, 1_899.63, 1_202.52}
    ],
    2 => [
      {7_789, 1_902.83, 1_223.41},
      {8_876, 1_889.82, 1_222.51},
      {7_787, 1_883.5, 1_218.25},
      {7_788, 1_883.74, 1_212.35},
      {8_877, 1_877.0, 1_207.27},
      {7_787, 1_890.08, 1_218.68},
      {7_789, 1_894.64, 1_206.29},
      {8_876, 1_877.4, 1_216.41},
      {7_787, 1_892.28, 1_225.49},
      {7_788, 1_893.07, 1_215.26},
      {8_877, 1_896.46, 1_205.62},
      {7_789, 1_874.45, 1_204.44},
      {7_789, 1_874.18, 1_221.24},
      {7_787, 1_879.02, 1_223.06},
      {8_876, 1_898.23, 1_217.97},
      {7_787, 1_882.07, 1_225.7},
      {8_877, 1_873.63, 1_204.65},
      {7_787, 1_886.97, 1_225.86},
      {7_788, 1_878.57, 1_214.16},
      {7_787, 1_894.72, 1_221.91},
      {7_787, 1_886.93, 1_221.4},
      {8_876, 1_883.76, 1_222.3},
      {7_788, 1_889.94, 1_212.21},
      {8_877, 1_899.63, 1_202.52}
    ],
    3 => [
      {7_788, 1_878.57, 1_214.16},
      {7_787, 1_894.72, 1_221.91},
      {7_787, 1_886.93, 1_221.4},
      {8_876, 1_883.76, 1_222.3},
      {7_788, 1_889.94, 1_212.21},
      {7_275, 1_889.23, 1_207.72},
      {7_796, 1_879.77, 1_207.96}
    ]
  }
  @wave_entries @waves |> Map.values() |> Enum.concat() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  @stair_top %{
    @bly => {1_887.17, 1_263.72, 41.484},
    @raven => {1_890.76, 1_265.82, 41.43},
    @oro => {1_883.3, 1_272.53, 41.87},
    @weegli => {1_883.87, 1_263.49, 41.55},
    @murta => {1_886.48, 1_272.76, 41.76}
  }
  @stair_foot %{
    @bly => {1_887.92, 1_228.179, 9.98},
    @murta => {1_891.57, 1_228.68, 9.69},
    @oro => {1_897.23, 1_228.34, 9.43},
    @raven => {1_883.68, 1_227.95, 9.543},
    @weegli => {1_878.02, 1_227.65, 9.485}
  }
  @pyramid_floor %{
    @bly => {1_883.82, 1_200.83, 8.87},
    @murta => {1_891.83, 1_201.45, 8.87},
    @oro => {1_894.50, 1_204.40, 8.87},
    @raven => {1_874.11, 1_206.17, 8.87},
    @weegli => {1_877.52, 1_199.63, 8.87}
  }

  def broadcast_text_ids, do: [@ukorz_yell]
  def summon_entries, do: @wave_entries
  def game_object_db_guids, do: []
  def registered_fields, do: [@pyramid, @gahzrilla, @end_door, @zumrah, @antusul]
  def door_entries, do: [@end_door_entry]
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def wave(number), do: Map.fetch!(@waves, number)

  def set_data(data, @pyramid, @arrived_at_stair) do
    if Encounter.value(data, @pyramid) in [@not_started, @cages_open],
      do: {:ok, @wave_1, Map.put(data, @pyramid, @wave_1), summon_wave(1) ++ [schedule(:send_adds, @first_group_ms)]},
      else: {:ok, Encounter.value(data, @pyramid), data, []}
  end

  def set_data(data, @end_door, value) do
    {:ok, stored, updated, effects} = Doors.put(doors(), data, @end_door, Encounter.settle(data, @end_door, value))
    yell = if stored == @done and not Encounter.done?(data, @end_door), do: [talk(@ukorz, @ukorz_yell)], else: []
    {:ok, stored, updated, effects ++ yell}
  end

  def set_data(data, field, value), do: {:ok, value, Map.put(data, field, value), []}

  def game_object_used(data, script_state, entry) when entry in @cages do
    if Encounter.value(data, @pyramid) == @not_started do
      {:ok, Map.put(data, @pyramid, @cages_open), script_state, free_crew()}
    else
      {:ok, data, script_state, []}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: entry, event: :spawned, db_guid: nil} = event)
      when entry in @wave_entries do
    script_state = ensure_script_state(script_state)

    case wave_number(data) do
      number when is_integer(number) ->
        if script_state.reported < length(wave(number)),
          do: {:ok, data, report(script_state, event.creature_guid), []},
          else: {:ok, data, script_state, []}

      nil ->
        {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :death} = event) when entry in @wave_entries do
    script_state = ensure_script_state(script_state)

    if MapSet.member?(script_state.alive, event.creature_guid) do
      script_state = %{
        script_state
        | alive: MapSet.delete(script_state.alive, event.creature_guid),
          at_base: List.delete(script_state.at_base, event.creature_guid)
      }

      if cleared?(data, script_state), do: clear_wave(data), else: {:ok, data, script_state, []}
    else
      {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, :send_adds) do
    script_state = ensure_script_state(script_state)

    if Encounter.value(data, @pyramid) in [@wave_1, @wave_2],
      do: send_adds(data, script_state),
      else: {:ok, data, script_state, []}
  end

  def timer(data, script_state, :wave_2) do
    if Encounter.value(data, @pyramid) == @pre_wave_2 do
      effects = summon_wave(2) ++ [schedule(:send_adds, @first_group_ms)]
      {:ok, Map.put(data, @pyramid, @wave_2), script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, :wave_3) do
    if Encounter.value(data, @pyramid) == @pre_wave_3,
      do: {:ok, Map.put(data, @pyramid, @wave_3), script_state, move_crew(@stair_foot, 4.78)},
      else: {:ok, data, script_state, []}
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp send_adds(data, script_state) do
    {group, at_base} = Enum.split(script_state.at_base, script_state.group_size)

    moves =
      group
      |> Enum.with_index(script_state.sent)
      |> Enum.map(fn {guid, index} -> climb(guid, index) end)

    script_state = %{
      script_state
      | at_base: at_base,
        group_size: script_state.group_size + 1,
        sent: script_state.sent + length(group)
    }

    more? = at_base != [] or script_state.reported < length(wave(wave_number(data)))
    effects = if more?, do: moves ++ [schedule(:send_adds, @group_interval_ms)], else: moves
    {:ok, data, script_state, effects}
  end

  defp climb(guid, index) do
    %Effects.RunCreatureScript{
      creature_entry: nil,
      creature_guid: guid,
      steps: [
        %ScriptStep{
          command: :move_to,
          datalong3: Bitwise.bor(@pathfind, @run),
          position: {1_880.0 + rem(index * 7, 11), 1_274.0, 42.0, 0.0}
        }
      ]
    }
  end

  defp clear_wave(data) do
    script_state = ensure_script_state(%{})

    case Encounter.value(data, @pyramid) do
      @wave_1 ->
        effects = [cancel(:send_adds), schedule(:wave_2, @wave_2_delay_ms)]
        {:ok, Map.put(data, @pyramid, @pre_wave_2), script_state, effects}

      @wave_2 ->
        effects = [cancel(:send_adds) | summon_wave(3)] ++ [schedule(:wave_3, @wave_3_delay_ms)]
        {:ok, Map.put(data, @pyramid, @pre_wave_3), script_state, effects}

      phase when phase in [@pre_wave_3, @wave_3] ->
        effects = [cancel(:wave_3) | move_crew(@pyramid_floor, 1.32)]
        {:ok, Map.put(data, @pyramid, @killed_all_trolls), script_state, effects}
    end
  end

  defp cleared?(data, script_state) do
    case wave_number(data) do
      nil -> false
      number -> script_state.reported == length(wave(number)) and MapSet.size(script_state.alive) == 0
    end
  end

  defp wave_number(data) do
    case Encounter.value(data, @pyramid) do
      @wave_1 -> 1
      @wave_2 -> 2
      phase when phase in [@pre_wave_3, @wave_3] -> 3
      _phase -> nil
    end
  end

  defp report(script_state, guid) do
    %{
      script_state
      | reported: script_state.reported + 1,
        alive: MapSet.put(script_state.alive, guid),
        at_base: script_state.at_base ++ [guid]
    }
  end

  defp summon_wave(number) do
    Enum.map(wave(number), fn {entry, x, y} ->
      %Effects.SummonCreature{
        entry: entry,
        position: {x, y, @floor_z, 0.0},
        despawn_type: @manual_despawn,
        despawn_delay_ms: 0
      }
    end)
  end

  defp free_crew do
    Enum.map(@stair_top, fn {entry, {x, y, z}} ->
      position = {x, y, z, 4.7}

      %Effects.RunCreatureScript{
        creature_entry: entry,
        steps: [
          %ScriptStep{command: :set_home_position, position: position},
          %ScriptStep{
            command: :move_to,
            datalong3: Bitwise.bor(@pathfind, @walk),
            datalong4: @inform,
            dataint: @at_stair,
            position: position
          },
          CreatureScript.faction(@freed)
        ]
      }
    end)
  end

  defp move_crew(positions, orientation) do
    Enum.map(positions, fn {entry, {x, y, z}} ->
      position = {x, y, z, orientation}

      %Effects.RunCreatureScript{
        creature_entry: entry,
        steps: [
          %ScriptStep{command: :set_home_position, position: position},
          %ScriptStep{command: :move_to, datalong3: Bitwise.bor(@pathfind, @walk), position: position}
        ]
      }
    end)
  end

  defp ensure_script_state(script_state) do
    Map.merge(%{reported: 0, alive: MapSet.new(), at_base: [], group_size: @first_group, sent: 0}, script_state)
  end

  defp doors, do: [{@end_door_entry, &Encounter.done?(&1, @end_door)}]

  defp talk(entry, text_id), do: %Effects.MonsterTalk{creature_entry: entry, broadcast_text_id: text_id}
  defp schedule(key, delay_ms), do: %Effects.Schedule{key: key, delay_ms: delay_ms}
  defp cancel(key), do: %Effects.CancelSchedules{keys: [key]}
end
