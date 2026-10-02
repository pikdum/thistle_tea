defmodule ThistleTea.Game.Core.InstanceScript.RazorfenKraul do
  @moduledoc """
  Agathelos' ward in Razorfen Kraul, after vmangos `instance_razorfen_kraul`.

  Each Death's Head Ward Keeper reports its death to the copy. When both have
  fallen the ward around Agathelos the Raging drops and he sets off at a run
  along his patrol, which he keeps if he spawns again later.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Doors
  alias ThistleTea.Game.Core.InstanceScript.Effects
  alias ThistleTea.Game.Core.InstanceScript.Encounter

  @agathelos_field 1
  @ward_keepers 2
  @slain_keepers :ward_keepers_slain
  @waypoint_motion 2

  @agathelos 4_422
  @ward 21_099

  def broadcast_text_ids, do: []
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: [@agathelos_field]
  def door_entries, do: [@ward]
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, @agathelos_field, value) do
    slain = Map.get(data, @slain_keepers, 0) + 1
    data = Map.put(data, @slain_keepers, slain)

    if slain == @ward_keepers do
      {:ok, stored, data, effects} = Doors.put(doors(), data, @agathelos_field, value)
      {:ok, stored, data, effects ++ [release_agathelos()]}
    else
      {:ok, Encounter.value(data, @agathelos_field), data, []}
    end
  end

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(data, _script_state, entry), do: {:ok, Doors.spawned(doors(), data, %{}, entry)}

  def creature_event(data, script_state, %{creature_entry: @agathelos, event: :spawned}) do
    effects = if Encounter.done?(data, @agathelos_field), do: [release_agathelos()], else: []
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp release_agathelos do
    %Effects.RunCreatureScript{
      creature_entry: @agathelos,
      steps: [
        %ScriptStep{command: :set_run, datalong: 1},
        %ScriptStep{command: :set_default_movement, datalong: @waypoint_motion}
      ]
    }
  end

  defp doors, do: [{@ward, &Encounter.done?(&1, @agathelos_field)}]
end
