defmodule ThistleTea.Game.Core.InstanceScript.Scholomance do
  @moduledoc """
  Darkmaster Gandling's summoning, the Brazier of the Herald, and the viewing
  room door, after vmangos `instance_scholomance`.

  The six room bosses report their deaths here, standing in for the vmangos
  boss scripts that set their encounter done. Once all six are dead,
  Darkmaster Gandling appears in the central hall. His own creature script
  reports failure when he returns home and success when he dies, and either
  one opens the six room gates his Shadow Portal may have shut.

  Lighting the Brazier of the Herald with the Blood of Innocents shuts the
  gate behind the party and calls Kirtonos the Herald. His death reopens the
  gate and settles the encounter, so the brazier will not call him twice. If
  he evades instead, his creature script reports failure, which reopens the
  gate and resets the brazier for another try.
  """

  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @gandling 0
  @theolen 1
  @malicia 2
  @illucia 3
  @alexei 4
  @polkelt 5
  @ravenian 6
  @kirtonos 7
  @viewing_room_door 14
  @darkreaver 15

  @in_progress 1
  @failed 2
  @done 3

  @room_bosses %{
    11_261 => @theolen,
    10_505 => @malicia,
    10_502 => @illucia,
    10_504 => @alexei,
    10_901 => @polkelt,
    10_507 => @ravenian
  }

  @gandling_entry 1_853
  @kirtonos_entry 10_506
  @gandling_position {180.771, -5.4286, 75.5702, 1.29154}
  @kirtonos_position {315.028, 70.53845, 102.1496, 0.3859715}
  @dead_despawn 7

  @kirtonos_gate 175_570
  @brazier 175_564
  @viewing_room 175_167
  @room_gates [177_371, 177_372, 177_373, 177_375, 177_376, 177_377]

  def broadcast_text_ids, do: []
  def summon_entries, do: [@gandling_entry, @kirtonos_entry]
  def game_object_db_guids, do: []

  def registered_fields,
    do: [
      @gandling,
      @theolen,
      @malicia,
      @illucia,
      @alexei,
      @polkelt,
      @ravenian,
      @kirtonos,
      @viewing_room_door,
      @darkreaver
    ]

  def door_entries, do: [@kirtonos_gate | @room_gates]
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @kirtonos, @failed) do
    {:ok, stored, data, effects} = put(data, @kirtonos, @failed)
    reset = if stored == @failed, do: [%Effects.OperateGameObject{entry: @brazier, action: :reset}], else: []
    {:ok, stored, data, effects ++ reset}
  end

  def set_data(data, field, value) do
    {:ok, stored, data, effects} = put(data, field, value)
    {data, summon} = summon_gandling(data)
    {:ok, stored, data, effects ++ summon}
  end

  def game_object_used(data, script_state, @brazier) do
    if Encounter.value(data, @kirtonos) in [@in_progress, @done] do
      {:ok, data, script_state, []}
    else
      {:ok, _stored, data, effects} = put(data, @kirtonos, @in_progress)
      {:ok, data, script_state, effects ++ [summon(@kirtonos_entry, @kirtonos_position)]}
    end
  end

  def game_object_used(data, script_state, @viewing_room) do
    {:ok, _stored, data, effects} = put(data, @viewing_room_door, @done)
    {:ok, data, script_state, effects}
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: @kirtonos_entry, event: :death}) do
    {:ok, _stored, data, effects} = put(data, @kirtonos, @done)
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :death})
      when is_map_key(@room_bosses, entry) do
    {:ok, _stored, data, effects} = set_data(data, Map.fetch!(@room_bosses, entry), @done)
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp put(data, field, value), do: Doors.put(doors(), data, field, Encounter.settle(data, field, value))

  defp summon_gandling(data) do
    if Encounter.value(data, @gandling) == 0 and Enum.all?(Map.values(@room_bosses), &Encounter.done?(data, &1)) do
      {:ok, _stored, data, effects} = put(data, @gandling, @in_progress)
      {data, effects ++ [summon(@gandling_entry, @gandling_position)]}
    else
      {data, []}
    end
  end

  defp summon(entry, position),
    do: %Effects.SummonCreature{entry: entry, position: position, despawn_delay_ms: 0, despawn_type: @dead_despawn}

  defp doors do
    room_gates = for gate <- @room_gates, do: {gate, &(Encounter.value(&1, @gandling) in [@failed, @done])}

    [
      {@kirtonos_gate, &(Encounter.value(&1, @kirtonos) != @in_progress)},
      {@viewing_room, &Encounter.done?(&1, @viewing_room_door)}
    ] ++ room_gates
  end
end
