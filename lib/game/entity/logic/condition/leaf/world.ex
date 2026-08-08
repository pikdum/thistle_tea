defmodule ThistleTea.Game.Entity.Logic.Condition.Leaf.World do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.InstanceDataSnapshot, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.Condition.Result
  alias ThistleTea.Game.Entity.Logic.Condition.Subject

  def evaluate(
        %Context{world: %{instance_data: %Snapshot{status: :available, fields: fields}}},
        %Condition{type: :instance_data, value1: field, value2: expected, value3: comparison} = condition
      ) do
    case Map.fetch(fields, field) do
      {:ok, {:ok, actual}} ->
        {:handled, Result.compare_result(actual, expected, comparison, condition)}

      {:ok, {:error, {:unsupported_field, ^field}}} ->
        {:handled, Result.unknown(condition, {:unsupported_instance_field, field})}

      {:ok, {:error, reason}} ->
        {:handled, Result.unknown(condition, {:invalid_instance_data, reason})}

      :error ->
        {:handled, Result.unknown(condition, {:missing_fact, :world, {:instance_data, field}})}
    end
  end

  def evaluate(
        %Context{world: %{instance_data: %Snapshot{status: status}}},
        %Condition{type: :instance_data} = condition
      ) do
    result =
      case status do
        :no_instance_script ->
          :unmet

        :open_world ->
          :unmet

        :missing_copy ->
          Result.unknown(condition, :missing_instance_copy)

        {:unsupported_script, script_name} ->
          Result.unknown(condition, {:unsupported_instance_script, script_name})

        other ->
          Result.unknown(condition, {:invalid_instance_snapshot, other})
      end

    {:handled, result}
  end

  def evaluate(%Context{}, %Condition{type: :instance_data} = condition) do
    {:handled, Result.unknown(condition, {:missing_fact, :world, :instance_data})}
  end

  def evaluate(%Context{source: %Subject{entry: entry}}, %Condition{type: :source_entry} = condition)
      when is_integer(entry), do: handled(matches_any_value?(entry, condition))

  def evaluate(%Context{source: %Subject{db_guid: db_guid}}, %Condition{type: :db_guid} = condition)
      when is_integer(db_guid) and db_guid > 0, do: handled(matches_any_value?(db_guid, condition))

  def evaluate(%Context{} = context, %Condition{type: :area_id, value1: area_id} = condition) do
    case first_world_subject(context) do
      %Subject{zone_id: zone, area_id: area} when is_integer(zone) or is_integer(area) ->
        handled(zone == area_id or area == area_id)

      _missing ->
        {:handled, Result.unknown(condition, {:missing_fact, :source_or_target, :area_id})}
    end
  end

  def evaluate(%Context{world: %{active_game_events: events}}, %Condition{type: :active_game_event, value1: event_id})
      when is_struct(events, MapSet), do: handled(MapSet.member?(events, event_id))

  def evaluate(
        %Context{content_patch: patch},
        %Condition{type: :content_patch, value1: expected, value2: comparison} = condition
      )
      when is_integer(patch), do: {:handled, Result.compare_result(patch, expected, comparison, condition)}

  def evaluate(%Context{} = context, %Condition{type: :map_id, value1: required} = condition) do
    case map_id(context) do
      map_id when is_integer(map_id) -> handled(map_id == required)
      _missing -> {:handled, Result.unknown(condition, {:missing_fact, :world, :map_id})}
    end
  end

  def evaluate(
        %Context{now: now},
        %Condition{type: :local_time, value1: start_hour, value2: start_minute, value3: end_hour, value4: end_minute} =
          condition
      ) do
    case local_hour_minute(now) do
      {hour, minute} ->
        handled({hour, minute} >= {start_hour, start_minute} and {hour, minute} <= {end_hour, end_minute})

      nil ->
        {:handled, Result.unknown(condition, :current_time)}
    end
  end

  def evaluate(%Context{target: %Subject{explored_areas: areas}}, %Condition{type: :area_explored, value1: area_id})
      when is_struct(areas, MapSet), do: handled(MapSet.member?(areas, area_id))

  def evaluate(%Context{target: %Subject{go_spawned?: spawned?}}, %Condition{type: :object_spawned})
      when is_boolean(spawned?), do: handled(spawned?)

  def evaluate(%Context{target: %Subject{loot_state: loot_state}}, %Condition{
        type: :object_loot_state,
        value1: required
      })
      when is_integer(loot_state), do: handled(loot_state == required)

  def evaluate(%Context{target: %Subject{go_state: go_state}}, %Condition{type: :object_go_state, value1: required})
      when is_integer(go_state), do: handled(go_state == required)

  def evaluate(_context, _condition), do: :unhandled

  defp handled(boolean), do: {:handled, Result.truth(boolean)}

  defp matches_any_value?(value, %Condition{value1: v1, value2: v2, value3: v3, value4: v4}) do
    value == v1 or (v2 != 0 and value == v2) or (v3 != 0 and value == v3) or (v4 != 0 and value == v4)
  end

  defp first_world_subject(%Context{source: %Subject{} = source}), do: source
  defp first_world_subject(%Context{target: %Subject{} = target}), do: target
  defp first_world_subject(%Context{}), do: nil

  defp map_id(%Context{world: %{map_id: map_id}}) when is_integer(map_id), do: map_id
  defp map_id(%Context{} = context), do: context |> first_world_subject() |> subject_map_id()

  defp subject_map_id(%Subject{map_id: map_id}), do: map_id
  defp subject_map_id(_subject), do: nil

  defp local_hour_minute(%DateTime{hour: hour, minute: minute}), do: {hour, minute}
  defp local_hour_minute(%NaiveDateTime{hour: hour, minute: minute}), do: {hour, minute}
  defp local_hour_minute(%Time{hour: hour, minute: minute}), do: {hour, minute}
  defp local_hour_minute(_now), do: nil
end
