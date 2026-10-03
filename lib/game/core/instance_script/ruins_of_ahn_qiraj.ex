defmodule ThistleTea.Game.Core.InstanceScript.RuinsOfAhnQiraj do
  @moduledoc """
  Lieutenant General Andorov's arrival in the Ruins of Ahn'Qiraj, after
  vmangos `instance_ruins_of_ahnqiraj`.

  Andorov and his four Kaldorei Elites are disabled spawns, held back until
  Kurinnaxx falls. His death loads the squad into the copy, and Andorov leads
  it along his path to the camp before General Rajaxx, where his waypoint
  script settles the elites around him. The Rajaxx event itself is not
  ported.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.InstanceScript.Effects

  @kurinnaxx 15_348
  @andorov 15_471
  @andorov_squad [301_311, 301_312, 301_313, 301_314, 301_315]
  @squad_loaded :andorov_squad_loaded?

  def broadcast_text_ids, do: []
  def summon_entries, do: []
  def game_object_db_guids, do: []
  def registered_fields, do: []
  def door_entries, do: []
  def data64(_index), do: nil
  def initial_value(_field), do: 0

  def set_data(data, _field, _value), do: {:ok, 0, data, []}

  def game_object_used(data, script_state, _entry), do: {:ok, data, script_state, []}

  def game_object_spawned(_data, _script_state, _entry), do: {:ok, []}

  def creature_event(data, script_state, %{creature_entry: @kurinnaxx, event: :death}) do
    if Map.get(script_state, @squad_loaded, false) do
      {:ok, data, script_state, []}
    else
      {:ok, data, Map.put(script_state, @squad_loaded, true), [%Effects.LoadCreatureSpawns{db_guids: @andorov_squad}]}
    end
  end

  def creature_event(data, script_state, %{creature_entry: @andorov, event: :spawned, creature_guid: guid}) do
    march = %Effects.RunCreatureScript{
      creature_entry: @andorov,
      creature_guid: guid,
      steps: [%ScriptStep{command: :start_waypoints}]
    }

    {:ok, data, script_state, [march]}
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}
end
