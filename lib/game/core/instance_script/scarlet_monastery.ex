defmodule ThistleTea.Game.Core.InstanceScript.ScarletMonastery do
  @moduledoc """
  The Scarlet Cathedral's Mograine and Whitemane encounter, after vmangos
  `instance_scarlet_monastery`.

  The two bosses' creature scripts in the world database report each stage:
  Mograine engages, falls the first time, is raised again, or leaves the fight.
  When Mograine engages, the chapel's defenders around his post join the
  fight, while Whitemane waits behind her door. When he falls the High
  Inquisitor's Door opens and Whitemane runs to raise him; once raised, both
  turn on everyone in the cathedral. A fight that ends with one of them dead
  removes the survivor and settles the encounter, and the door shuts again
  when it resets.

  Herod's death in the Armory opens the door behind him, which stays open
  if it respawns.

  The Ashbringer event is recorded but not played.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @mograine_and_whitemane 1
  @ashbringer 2

  @not_started 0
  @in_progress 1
  @died_once 2
  @revived 3
  @done 4

  @data_mograine 2
  @data_whitemane 3
  @mograine 3_976
  @whitemane 3_977
  @mograine_spawn 40_029
  @whitemane_spawn 39_946
  @slain :cathedral_slain

  @high_inquisitors_door 104_600
  @herods_door 101_854
  @herod 3_975
  @herod_slain :herod_slain
  @yell_whitemane 2_973
  @defenders [4_299, 4_300, 4_301, 4_302, 4_303, 4_540]
  @defender_reach {{1_153.87, 1_398.39, 32.61}, 82.0}
  @resurrection_point 100
  @pathfinding_run 69

  def broadcast_text_ids, do: [@yell_whitemane]
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: [@mograine_and_whitemane, @ashbringer]
  def door_entries, do: [@high_inquisitors_door]
  def data64(@data_mograine), do: @mograine_spawn
  def data64(@data_whitemane), do: @whitemane_spawn
  def data64(_index), do: nil
  def initial_value(_field), do: @not_started

  def set_data(data, @mograine_and_whitemane, value) do
    current = Encounter.value(data, @mograine_and_whitemane)

    cond do
      current == @done -> {:ok, @done, data, []}
      value == @not_started and slain(data) != [] -> settle(data)
      true -> stage(data, current, value)
    end
  end

  def set_data(data, field, value), do: Doors.put(doors(), data, field, value)

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: entry, event: :death})
      when entry in [@mograine, @whitemane] do
    data = Map.put(data, @slain, Enum.uniq([entry | slain(data)]))

    if length(slain(data)) == 2 do
      {:ok, _stored, data, effects} = Doors.put(doors(), data, @mograine_and_whitemane, @done)
      {:ok, data, script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, %{creature_entry: @herod, event: :death}) do
    {:ok, _stored, data, effects} = Doors.put(doors(), data, @herod_slain, true)
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :spawned})
      when entry in [@mograine, @whitemane] do
    cond do
      Encounter.value(data, @mograine_and_whitemane) == @done -> {:ok, data, script_state, [despawn(entry)]}
      entry in slain(data) -> {:ok, Map.put(data, @slain, List.delete(slain(data), entry)), script_state, []}
      true -> {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp stage(data, current, value) do
    {:ok, stored, data, effects} = Doors.put(doors(), data, @mograine_and_whitemane, value)
    {:ok, stored, data, effects ++ stage_effects(current, value, @whitemane in slain(data))}
  end

  defp settle(data) do
    {:ok, stored, data, effects} = Doors.put(doors(), data, @mograine_and_whitemane, @done)
    survivors = [@mograine, @whitemane] -- slain(data)
    {:ok, stored, data, effects ++ Enum.map(survivors, &despawn/1)}
  end

  defp stage_effects(_current, @in_progress, _whitemane_slain?), do: Enum.map(@defenders, &defender_joins/1)
  defp stage_effects(@died_once, @not_started, false), do: [reset_whitemane()]
  defp stage_effects(_current, @died_once, false), do: [whitemane_yell(), whitemane_to_mograine()]
  defp stage_effects(_current, @revived, _whitemane_slain?), do: [zone_combat(@mograine), zone_combat(@whitemane)]
  defp stage_effects(_current, _value, _whitemane_slain?), do: []

  defp defender_joins(entry) do
    %Effects.RunCreatureScript{
      creature_entry: entry,
      within: @defender_reach,
      steps: [%ScriptStep{command: :zone_combat_pulse, datalong: 1}]
    }
  end

  defp whitemane_to_mograine do
    %Effects.RunCreatureScript{
      creature_entry: @whitemane,
      steps: [
        %ScriptStep{
          command: :move_to,
          datalong: 2,
          datalong3: @pathfinding_run,
          datalong4: 2,
          dataint: @resurrection_point,
          target_type: :creature_from_instance_data,
          target_param1: @data_mograine,
          position: {3.0, 0.0, 0.0, 0.0}
        }
      ]
    }
  end

  defp reset_whitemane,
    do: %Effects.RunCreatureScript{
      creature_entry: @whitemane,
      steps: [%ScriptStep{command: :respawn_creature, datalong: 0}]
    }

  defp zone_combat(entry),
    do: %Effects.RunCreatureScript{
      creature_entry: entry,
      steps: [%ScriptStep{command: :zone_combat_pulse, datalong: 1}]
    }

  defp despawn(entry),
    do: %Effects.RunCreatureScript{creature_entry: entry, steps: [%ScriptStep{command: :despawn, datalong: 0}]}

  defp whitemane_yell, do: %Effects.MonsterTalk{creature_entry: @whitemane, broadcast_text_id: @yell_whitemane}

  defp slain(data), do: Map.get(data, @slain, [])

  defp doors do
    [
      {@high_inquisitors_door, &(Encounter.value(&1, @mograine_and_whitemane) in [@died_once, @revived, @done])},
      {@herods_door, &Map.get(&1, @herod_slain, false)}
    ]
  end
end
