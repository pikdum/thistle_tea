defmodule ThistleTea.Game.World.Loader.Script do
  @moduledoc """
  Loads generic script-command rows (`creature_ai_scripts`,
  `creature_movement_scripts`, `generic_scripts`, …) into `ScriptStep`
  structs grouped by script id, resolving the broadcast texts referenced by
  talk steps, mount-by-entry steps into display ids, and recursively the
  `generic_scripts` referenced by start-script and summon steps
  (cycle-guarded), so the runtime interpreter never touches the database.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader

  def load_by_ids(schema, script_ids), do: load_by_ids(schema, script_ids, MapSet.new())

  defp load_by_ids(_schema, [], _visited), do: %{}

  defp load_by_ids(schema, script_ids, visited) when is_list(script_ids) do
    script_ids
    |> Enum.uniq()
    |> schema.query()
    |> Mangos.Repo.all()
    |> Enum.map(&ScriptStep.build/1)
    |> Enum.map(&resolve_mount_display/1)
    |> resolve_buddy_guids()
    |> resolve_texts()
    |> resolve_nested_scripts(visited)
    |> attach_conditions()
    |> Enum.group_by(& &1.script_id)
  end

  defp resolve_mount_display(%ScriptStep{command: :mount, datalong2: 0, datalong: entry} = step) when entry > 0 do
    with %Mangos.CreatureTemplate{} = template <- Mangos.Repo.get(Mangos.CreatureTemplate, entry),
         display_id when is_integer(display_id) <-
           Enum.find(
             [template.model_id1, template.model_id2, template.model_id3, template.model_id4],
             &(is_integer(&1) and &1 > 0)
           ) do
      %{step | datalong: display_id, datalong2: 1}
    else
      _ -> step
    end
  end

  defp resolve_mount_display(%ScriptStep{} = step), do: step

  defp resolve_buddy_guids(steps) do
    creature_guids = buddy_db_guids(steps, :creature_with_guid)
    game_object_guids = buddy_db_guids(steps, :game_object_with_guid)

    creatures =
      from(c in Mangos.Creature, where: c.guid in ^creature_guids)
      |> Mangos.Repo.all()
      |> Map.new(&{&1.guid, Guid.from_low_guid(:mob, &1.id, &1.guid)})

    game_objects =
      from(g in Mangos.GameObject, where: g.guid in ^game_object_guids)
      |> Mangos.Repo.all()
      |> Map.new(&{&1.guid, Guid.from_low_guid(:game_object, &1.id, &1.guid)})

    Enum.map(steps, fn
      %ScriptStep{target_type: :creature_with_guid, target_param1: db_guid} = step ->
        %{step | buddy_guid: Map.get(creatures, db_guid)}

      %ScriptStep{target_type: :game_object_with_guid, target_param1: db_guid} = step ->
        %{step | buddy_guid: Map.get(game_objects, db_guid)}

      %ScriptStep{} = step ->
        step
    end)
  end

  defp buddy_db_guids(steps, target_type) do
    steps
    |> Enum.filter(&(&1.target_type == target_type))
    |> Enum.map(& &1.target_param1)
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.uniq()
  end

  defp resolve_nested_scripts(steps, visited) do
    nested_ids =
      steps
      |> Enum.flat_map(&ScriptStep.nested_script_ids/1)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(visited, &1))

    if nested_ids == [] do
      steps
    else
      visited = Enum.into(nested_ids, visited)
      sub_scripts = load_by_ids(Mangos.GenericScript, nested_ids, visited)
      Enum.map(steps, &attach_sub_scripts(&1, sub_scripts))
    end
  end

  defp attach_sub_scripts(%ScriptStep{} = step, sub_scripts) do
    case ScriptStep.nested_script_ids(step) do
      [] -> step
      script_ids -> %{step | sub_scripts: Map.new(script_ids, &{&1, Map.get(sub_scripts, &1, [])})}
    end
  end

  defp resolve_texts(steps) do
    texts_by_id =
      steps
      |> Enum.flat_map(&ScriptStep.talk_text_ids/1)
      |> load_broadcast_texts()

    Enum.map(steps, fn
      %ScriptStep{command: :talk} = step ->
        texts =
          step
          |> ScriptStep.talk_text_ids()
          |> Enum.flat_map(&List.wrap(Map.get(texts_by_id, &1)))

        %{step | texts: texts}

      step ->
        step
    end)
  end

  defp load_broadcast_texts([]), do: %{}

  defp load_broadcast_texts(text_ids) do
    from(t in Mangos.BroadcastText, where: t.entry in ^Enum.uniq(text_ids))
    |> Mangos.Repo.all()
    |> Map.new(fn row -> {row.entry, build_text(row)} end)
  end

  defp attach_conditions(steps) do
    conditions =
      steps
      |> Enum.flat_map(&with_sub_steps/1)
      |> Enum.flat_map(&ScriptStep.condition_ids/1)
      |> ConditionLoader.load_by_ids()

    Enum.map(steps, &attach_step_condition(&1, conditions))
  end

  defp with_sub_steps(%ScriptStep{} = step) do
    [step | step.sub_scripts |> Map.values() |> List.flatten() |> Enum.flat_map(&with_sub_steps/1)]
  end

  defp attach_step_condition(%ScriptStep{} = step, conditions) do
    sub_scripts =
      Map.new(step.sub_scripts, fn {script_id, steps} ->
        {script_id, Enum.map(steps, &attach_step_condition(&1, conditions))}
      end)

    %{
      step
      | condition: Map.get(conditions, step.condition_id),
        success_condition: map_event_condition(step, conditions, :success),
        failure_condition: map_event_condition(step, conditions, :failure),
        target_condition: map_event_condition(step, conditions, :target),
        sub_scripts: sub_scripts
    }
  end

  defp map_event_condition(%ScriptStep{command: command, dataint: id}, conditions, :success)
       when command in [:start_map_event, :add_map_event_target, :edit_map_event], do: Map.get(conditions, id)

  defp map_event_condition(%ScriptStep{command: command, dataint3: id}, conditions, :failure)
       when command in [:start_map_event, :add_map_event_target, :edit_map_event], do: Map.get(conditions, id)

  defp map_event_condition(%ScriptStep{command: :remove_map_event_target, datalong2: id}, conditions, :target),
    do: Map.get(conditions, id)

  defp map_event_condition(%ScriptStep{}, _conditions, _kind), do: nil

  defp build_text(%Mangos.BroadcastText{} = row) do
    %{
      text: text(row),
      chat_type: chat_type(row.chat_type),
      language: row.language_id || 0,
      emote_id: row.emote_id1 || 0
    }
  end

  defp text(%Mangos.BroadcastText{male_text: male, female_text: female}) do
    cond do
      is_binary(male) and male != "" -> male
      is_binary(female) and female != "" -> female
      true -> ""
    end
  end

  def chat_type(1), do: :yell
  def chat_type(2), do: :text_emote
  def chat_type(3), do: :boss_emote
  def chat_type(4), do: :whisper
  def chat_type(5), do: :boss_whisper
  def chat_type(6), do: :zone_yell
  def chat_type(7), do: :zone_emote
  def chat_type(_other), do: :say
end
