defmodule ThistleTea.Game.Core.InstanceScript.BlackfathomDeeps do
  @moduledoc """
  The Fire of Aku'mai shrine event and the Portal of Aku'Mai, after vmangos
  `instance_blackfathom_deeps`.

  Twilight Lord Kelris' death, reported by his creature script, opens the
  shrine. Each Fire of Aku'mai lit after that calls the next of four waves of
  Aku'mai's servants three seconds later, in the order the fires are lit, not
  by which fire it was. Once all four fires burn and every called servant has
  died, the shrine is done, and with Kelris dead the portal to Aku'mai opens.
  A fire lit while Kelris lives flickers out again, the way a vmangos button
  resets when its script turns the use down.

  Servants are counted out as they die rather than checked alive once a
  second, and like vmangos they stay where they are after a wipe.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @kelris 10
  @shrine 11
  @aquanis 12

  @in_progress 1
  @done 3

  @portal 21_117
  @fires [21_118, 21_119, 21_120, 21_121]

  @snapjaw 4_825
  @servant 4_978
  @snapclaw 4_815
  @softshell 4_977
  @servant_entries [@snapjaw, @servant, @snapclaw, @softshell]

  @summoned_demon_visual 7_741
  @triggered 0x02
  @wave_delay_ms 3_000
  @fire_reset_ms 1_000
  @interaction_distance 5.0

  @spawn_points {
    {-768.949, -174.413, -25.87, 3.09},
    {-768.888, -164.238, -25.87, 3.09},
    {-768.951, -153.911, -25.88, 3.09},
    {-867.782, -174.352, -25.87, 6.27},
    {-867.875, -164.089, -25.87, 6.27},
    {-867.859, -153.927, -25.88, 6.27}
  }

  @waves %{
    0 => [{@snapjaw, [{1, 0}, {1, 1}, {1, 5}]}, {@snapjaw, [{1, 4}]}],
    1 => [{@servant, [{1, 1}, {1, 4}]}],
    2 => [{@snapclaw, [{1, 0}, {1, 2}]}, {@snapclaw, [{1, 3}, {1, 4}]}],
    3 => [{@softshell, [{2, 0}, {1, 1}, {1, 2}]}, {@softshell, [{1, 3}, {1, 4}, {2, 5}]}]
  }

  def broadcast_text_ids, do: []
  def summon_entries, do: @servant_entries
  def game_object_db_guids, do: []
  def registered_fields, do: [@kelris, @shrine, @aquanis]
  def door_entries, do: Enum.map(doors(), &elem(&1, 0))
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, field, value), do: Doors.put(doors(), data, field, Encounter.settle(data, field, value))

  def game_object_used(data, script_state, entry) when entry in @fires do
    lit = lit(script_state)

    cond do
      entry in lit ->
        {:ok, data, script_state, []}

      not Encounter.done?(data, @kelris) ->
        {:ok, data, script_state, [%Effects.Schedule{key: {:fire_reset, entry}, delay_ms: @fire_reset_ms}]}

      true ->
        wave = length(lit)
        script_state = Map.put(script_state, :lit, lit ++ [entry])
        {:ok, _stored, data, effects} = set_data(data, @shrine, @in_progress)
        {:ok, data, script_state, effects ++ [%Effects.Schedule{key: {:wave, wave}, delay_ms: @wave_delay_ms}]}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(_data, script_state, entry) when entry in @fires do
    effects = if entry in lit(script_state), do: [operate(entry, :open)], else: []
    {:ok, effects}
  end

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: entry, event: :death, db_guid: nil})
      when entry in @servant_entries do
    case Map.get(script_state, :remaining, 0) do
      remaining when remaining > 0 -> settle_shrine(data, Map.put(script_state, :remaining, remaining - 1))
      _none -> {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, {:fire_reset, entry}) do
    effects = if entry in lit(script_state), do: [], else: [operate(entry, :reset)]
    {:ok, data, script_state, effects}
  end

  def timer(data, script_state, {:wave, wave}) when is_map_key(@waves, wave) do
    summons = wave_summons(wave)

    script_state =
      script_state
      |> Map.update(:remaining, length(summons), &(&1 + length(summons)))
      |> Map.update(:waves, 1, &(&1 + 1))

    {:ok, data, script_state, summons}
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp settle_shrine(data, script_state) do
    if Map.get(script_state, :waves, 0) == map_size(@waves) and script_state.remaining == 0 do
      {:ok, _stored, data, effects} = set_data(data, @shrine, @done)
      {:ok, data, script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  defp wave_summons(wave) do
    for {entry, groups} <- Map.fetch!(@waves, wave),
        {count, point} <- groups,
        index <- 0..(count - 1)//1 do
      {x, y, z, o} = elem(@spawn_points, point)
      y = if count > 1, do: y - @interaction_distance / 2 + index * @interaction_distance / count, else: y

      %Effects.SummonCreature{
        entry: entry,
        position: {x, y, z, o},
        despawn_delay_ms: 0,
        despawn_type: 7,
        steps: [
          %ScriptStep{
            command: :cast_spell,
            datalong: @summoned_demon_visual,
            datalong2: @triggered,
            target_self?: true
          },
          %ScriptStep{command: :zone_combat_pulse, datalong: 1}
        ]
      }
    end
  end

  defp lit(script_state), do: Map.get(script_state, :lit, [])

  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}

  defp doors, do: [{@portal, &(Encounter.done?(&1, @kelris) and Encounter.done?(&1, @shrine))}]
end
