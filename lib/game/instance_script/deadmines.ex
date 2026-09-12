defmodule ThistleTea.Game.InstanceScript.Deadmines do
  @moduledoc """
  Deadmines boss doors and the gunpowder-to-cannon breach sequence.
  Encounter state and timed transitions belong to each dungeon copy.
  """

  alias ThistleTea.Game.InstanceScript.Effects

  @end_door 1
  @gunpowder 5_000
  @boss_doors %{644 => {10, 13_965}, 643 => {11, 16_400}, 1_763 => {12, 16_399}}
  @pirates [79_289, 79_290]

  def broadcast_text_ids, do: [1_148, 1_149]
  def summon_entries, do: [634]
  def registered_fields, do: [@end_door, @gunpowder, 10, 11, 12]
  def initial_value(_field), do: 0

  def set_data(data, @end_door, 1) do
    if Map.get(data, @end_door, 0) == 0 do
      effects = [
        operate(16_398, :open),
        operate(16_397, :destroy),
        %Effects.Schedule{key: :deadmines_alarm, delay_ms: 3_000}
      ]

      {:ok, 1, Map.put(data, @end_door, 1), effects}
    else
      {:ok, Map.fetch!(data, @end_door), data, []}
    end
  end

  def set_data(data, field, value), do: {:ok, value, Map.put(data, field, value), []}

  def game_object_used(data, 17_155) do
    if Map.get(data, @gunpowder, 0) == 0 do
      effect = %Effects.SummonCreature{
        entry: 634,
        position: {-131.290833, -591.243103, 18.077190, 4.792192},
        move_to: {-115.263672, -617.396118, 13.579387},
        despawn_delay_ms: 310_000
      }

      {:ok, Map.put(data, @gunpowder, 1), [effect]}
    else
      {:ok, data, []}
    end
  end

  def game_object_used(data, 16_398) do
    {:ok, _stored, data, effects} = set_data(data, @end_door, 1)
    {:ok, data, effects}
  end

  def game_object_used(data, _entry), do: {:ok, data, []}

  def game_object_spawned(data, _script_state, entry) do
    effects =
      cond do
        entry == 16_397 and Map.get(data, @end_door, 0) > 0 -> [operate(entry, :destroy)]
        entry == 16_398 and Map.get(data, @end_door, 0) > 0 -> [operate(entry, :open)]
        completed_door?(data, entry) -> [operate(entry, :open)]
        true -> []
      end

    {:ok, effects}
  end

  def creature_event(data, script_state, %{creature_entry: entry, event: :death}) when is_map_key(@boss_doors, entry) do
    {field, door} = Map.fetch!(@boss_doors, entry)
    effects = if Map.get(data, field, 0) == 3, do: [], else: [operate(door, :open)]
    {:ok, Map.put(data, field, 3), script_state, effects}
  end

  def creature_event(data, script_state, %{creature_entry: 657, event: :spawned, db_guid: db_guid})
      when db_guid in @pirates do
    effects = if Map.get(data, @end_door, 0) in [2, 3], do: [move_pirate(db_guid)], else: []
    {:ok, data, script_state, effects}
  end

  def creature_event(data, script_state, _event), do: {:ok, data, script_state, []}

  def timer(data, script_state, :deadmines_alarm) do
    if Map.get(data, @end_door, 0) == 1 do
      effects =
        [talk(1_148)] ++
          Enum.map(@pirates, &move_pirate/1) ++
          [%Effects.Schedule{key: :deadmines_attack, delay_ms: 15_000}]

      {:ok, Map.put(data, @end_door, 2), script_state, effects}
    else
      {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, :deadmines_attack) do
    if Map.get(data, @end_door, 0) == 2 do
      {:ok, Map.put(data, @end_door, 3), script_state, [talk(1_149)]}
    else
      {:ok, data, script_state, []}
    end
  end

  def timer(data, script_state, _key), do: {:ok, data, script_state, []}

  defp completed_door?(data, entry) do
    Enum.any?(@boss_doors, fn {_boss, {field, door}} -> door == entry and Map.get(data, field, 0) == 3 end)
  end

  defp move_pirate(db_guid) do
    %Effects.MoveCreature{
      creature_entry: 657,
      creature_db_guid: db_guid,
      position: {-99.6611, -671.071655, 7.42241}
    }
  end

  defp talk(text), do: %Effects.MonsterTalk{creature_entry: 646, broadcast_text_id: text}
  defp operate(entry, action), do: %Effects.OperateGameObject{entry: entry, action: action}
end
