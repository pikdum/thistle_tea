defmodule ThistleTea.Game.Core.InstanceScript.SunkenTemple do
  @moduledoc """
  Jammal'an's barrier and the Shade of Eranikus' slumber in the Temple of
  Atal'Hakkar, after vmangos `instance_sunken_temple`.

  The forcefield before Jammal'an the Prophet drops once all six of his troll
  protectors are dead, and he calls out to the intruders. The Shade of Eranikus
  sleeps out of reach until Jammal'an falls, and wakes when he is attacked.

  The Atal'ai statue circle, Atal'alarion, Dreamscythe and Weaver's entrance and
  the Avatar of Hakkar are not part of this port.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @secret_circle 4
  @protectors_field 5
  @jammalan_field 6
  @malfurion 7
  @avatar 8
  @eranikus_field 9
  @eternal_flame 10

  @done 3
  @slain_protectors :protectors_slain
  @protectors [5_712, 5_713, 5_714, 5_715, 5_716, 5_717]
  @jammalan 5_710
  @shade_of_eranikus 5_709
  @barrier 149_431
  @yell_jammalan 4_490

  @unit_flags_field 46
  @immune_to_player 0x100
  @set_flags 1
  @remove_flags 2
  @stand 0
  @sleep 3

  def broadcast_text_ids, do: [@yell_jammalan]
  def summon_entries, do: []
  def game_object_db_guids, do: []

  def registered_fields,
    do: [@secret_circle, @protectors_field, @jammalan_field, @malfurion, @avatar, @eranikus_field, @eternal_flame]

  def door_entries, do: [@barrier]
  def initial_value(_field), do: 0

  def set_data(data, @protectors_field, _value), do: {:ok, Encounter.value(data, @protectors_field), data, []}

  def set_data(data, @jammalan_field, value) do
    {:ok, stored, updated, effects} =
      Doors.put(doors(), data, @jammalan_field, Encounter.settle(data, @jammalan_field, value))

    wake = if Encounter.done?(data, @jammalan_field) or stored != @done, do: [], else: [eranikus(@remove_flags, @sleep)]
    {:ok, stored, updated, effects ++ wake}
  end

  def set_data(data, field, value), do: Doors.put(doors(), data, field, Encounter.settle(data, field, value))

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: entry, event: :death}) when entry in @protectors do
    slain = data |> Map.get(@slain_protectors, []) |> then(&Enum.uniq([entry | &1]))
    data = Map.put(data, @slain_protectors, slain)

    if Encounter.done?(data, @protectors_field) or length(slain) < length(@protectors) do
      {:ok, data, script_state, []}
    else
      {:ok, _stored, data, effects} = Doors.put(doors(), data, @protectors_field, @done)
      yell = %Effects.MonsterTalk{creature_entry: @jammalan, broadcast_text_id: @yell_jammalan}
      {:ok, data, script_state, effects ++ [yell]}
    end
  end

  def creature_event(data, script_state, %{creature_entry: @shade_of_eranikus, event: :spawned}) do
    effects = if Encounter.done?(data, @jammalan_field), do: [], else: [eranikus(@set_flags, @sleep)]
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: @shade_of_eranikus, event: :aggro}),
    do: {:ok, data, script_state, [eranikus(@remove_flags, @stand)]}

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp eranikus(immunity, stand_state) do
    %Effects.RunCreatureScript{
      creature_entry: @shade_of_eranikus,
      steps: [
        %ScriptStep{
          command: :modify_flags,
          datalong: @unit_flags_field,
          datalong2: @immune_to_player,
          datalong3: immunity
        },
        %ScriptStep{command: :stand_state, datalong: stand_state}
      ]
    }
  end

  defp doors, do: [{@barrier, &Encounter.done?(&1, @protectors_field)}]
end
