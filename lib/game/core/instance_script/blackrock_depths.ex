defmodule ThistleTea.Game.Core.InstanceScript.BlackrockDepths do
  @moduledoc """
  Blackrock Depths progression doors and the Tomb of the Seven, after vmangos
  `instance_blackrock_depths`.

  Lighting both Shadowforge Braziers opens the Golem Room doors out of the
  Lyceum. Magmus closes them behind challengers while he fights, and his death
  opens them and the Throne Room. Challenging Doom'rel seals the tomb and calls
  the Seven down one at a time, thirty seconds apart; when a called dwarf gives
  up its fight they all stand down, and Doom'rel's death opens the way out and
  raises the Chest of the Seven. Ambassador Flamelash lights the dwarf runes
  while he fights.

  The Lyceum stays complete once its braziers are lit, where vmangos lets a
  Seven dwarf walking home record a failure over it. A wipe on the Seven is
  noticed when a called dwarf leaves combat, rather than by checking its victim
  shortly after each call.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @tomb_of_seven 3
  @lyceum 4
  @iron_hall 5
  @flamelash 43

  @not_started 0
  @in_progress 1
  @fail 2
  @done 3

  @braziers [174_744, 174_745]
  @golem_doors [170_573, 170_574]
  @throne_room 170_575
  @tomb_enter 170_576
  @tomb_exit 170_577
  @dwarf_runes Enum.to_list(170_578..170_584)
  @chest_of_seven 399_065
  @chest_respawn_ms 3_600_000

  @magmus 9_938
  @doomrel 9_039
  @seven [9_035, 9_038, 9_040, 9_037, 9_036, 9_034, @doomrel]
  @hostile_faction 54
  @unit_flags_field 46
  @immune_to_player 0x100
  @set_flags 1
  @remove_flags 2
  @restore_on_respawn 0x01
  @call_ms 30_000
  @pulse_delay_ms 500
  @yell_magmus 5_430

  def broadcast_text_ids, do: [@yell_magmus]
  def summon_entries, do: []
  def game_object_db_guids, do: [@chest_of_seven]
  def registered_fields, do: [@tomb_of_seven, @lyceum, @iron_hall, @flamelash]
  def door_entries, do: Enum.map(doors(), &elem(&1, 0))
  def data64(_index), do: nil
  def initial_value(_field), do: @not_started

  def set_data(data, @lyceum, value) do
    value = if value(data, @lyceum) == @done, do: @done, else: value
    {:ok, stored, updated, effects} = Doors.put(doors(), data, @lyceum, value)
    yell = if value(data, @lyceum) != @done and stored == @done, do: [magmus_yell()], else: []
    {:ok, stored, updated, effects ++ yell}
  end

  def set_data(data, @tomb_of_seven, value), do: set_tomb(data, value(data, @tomb_of_seven), value)
  def set_data(data, field, value), do: Doors.put(doors(), data, field, value)

  def game_object_used(data, script_state, entry) when entry in @braziers do
    lit = Map.get(script_state, :lyceum_brazier)

    case value(data, @lyceum) do
      @done ->
        {:ok, data, script_state, []}

      @in_progress when lit == entry ->
        {:ok, data, script_state, []}

      @in_progress ->
        {:ok, _stored, data, effects} = set_data(data, @lyceum, @done)
        {:ok, data, script_state, effects}

      _state ->
        {:ok, _stored, data, effects} = set_data(data, @lyceum, @in_progress)
        {:ok, data, Map.put(script_state, :lyceum_brazier, entry), effects}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: @magmus, event: event})
      when event in [:aggro, :evade, :death] do
    {:ok, _stored, data, effects} = set_data(data, @iron_hall, iron_hall(event))
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: @doomrel, event: :death}) do
    {:ok, _stored, data, effects} = set_data(data, @tomb_of_seven, @done)
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :evade}) when entry in @seven do
    if value(data, @tomb_of_seven) == @in_progress do
      {:ok, _stored, data, effects} = set_data(data, @tomb_of_seven, @fail)
      {:ok, data, script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, {:tomb_call, round}) when round in 0..6 do
    if value(data, @tomb_of_seven) == @in_progress do
      {:ok, data, script_state, [call_to_fight(Enum.at(@seven, round)) | next_call(round + 1)]}
    else
      {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp set_tomb(data, @not_started, @in_progress) do
    {:ok, stored, data, effects} = Doors.put(doors(), data, @tomb_of_seven, @in_progress)
    {:ok, stored, data, effects ++ [%Effects.Schedule{key: {:tomb_call, 0}, delay_ms: 0}]}
  end

  defp set_tomb(data, @in_progress, @fail) do
    {:ok, stored, data, effects} = Doors.put(doors(), data, @tomb_of_seven, @not_started)
    {:ok, stored, data, effects ++ [cancel_calls() | Enum.map(@seven, &stand_down/1)]}
  end

  defp set_tomb(data, current, @done) when current != @done do
    {:ok, stored, data, effects} = Doors.put(doors(), data, @tomb_of_seven, @done)
    chest = %Effects.RespawnGameObject{db_guid: @chest_of_seven, duration_ms: @chest_respawn_ms}
    {:ok, stored, data, effects ++ [cancel_calls(), chest]}
  end

  defp set_tomb(data, current, @not_started) when current != @in_progress,
    do: Doors.put(doors(), data, @tomb_of_seven, @not_started)

  defp set_tomb(data, current, _value), do: {:ok, current, data, []}

  defp next_call(round) when round < length(@seven),
    do: [%Effects.Schedule{key: {:tomb_call, round}, delay_ms: @call_ms}]

  defp next_call(_round), do: []

  defp cancel_calls, do: %Effects.CancelSchedules{keys: Enum.map(0..6, &{:tomb_call, &1})}

  defp call_to_fight(entry) do
    %Effects.RunCreatureScript{
      creature_entry: entry,
      steps: [
        immunity(@remove_flags),
        %ScriptStep{command: :set_faction, datalong: @hostile_faction, datalong2: @restore_on_respawn},
        %ScriptStep{command: :zone_combat_pulse, datalong: 1, delay_ms: @pulse_delay_ms}
      ]
    }
  end

  defp stand_down(entry) do
    %Effects.RunCreatureScript{
      creature_entry: entry,
      steps: [
        %ScriptStep{command: :set_faction, datalong: 0},
        immunity(@set_flags),
        %ScriptStep{command: :respawn_creature, datalong: 0}
      ]
    }
  end

  defp immunity(mode),
    do: %ScriptStep{command: :modify_flags, datalong: @unit_flags_field, datalong2: @immune_to_player, datalong3: mode}

  defp iron_hall(:aggro), do: @in_progress
  defp iron_hall(:evade), do: @fail
  defp iron_hall(:death), do: @done

  defp magmus_yell, do: %Effects.MonsterTalk{creature_entry: @magmus, broadcast_text_id: @yell_magmus}

  defp doors do
    golem_doors = Enum.map(@golem_doors, &{&1, fn data -> golem_doors_open?(data) end})
    runes = Enum.map(@dwarf_runes, &{&1, fn data -> value(data, @flamelash) == @in_progress end})

    golem_doors ++
      runes ++
      [
        {@throne_room, &(value(&1, @iron_hall) == @done)},
        {@tomb_exit, &(value(&1, @tomb_of_seven) == @done)},
        {@tomb_enter, &(value(&1, @tomb_of_seven) != @in_progress)}
      ]
  end

  defp golem_doors_open?(data), do: value(data, @lyceum) == @done and value(data, @iron_hall) != @in_progress

  defp value(data, field), do: Map.get(data, field, @not_started)
end
