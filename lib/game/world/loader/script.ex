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

  def load_by_ids(schema, script_ids), do: load_by_ids(schema, script_ids, MapSet.new())

  defp load_by_ids(_schema, [], _visited), do: %{}

  defp load_by_ids(schema, script_ids, visited) when is_list(script_ids) do
    script_ids
    |> Enum.uniq()
    |> schema.query()
    |> Mangos.Repo.all()
    |> Enum.map(&ScriptStep.build/1)
    |> Enum.map(&resolve_mount_display/1)
    |> Enum.map(&resolve_buddy_guid/1)
    |> resolve_texts()
    |> resolve_nested_scripts(visited)
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

  defp resolve_buddy_guid(%ScriptStep{target_type: :creature_with_guid, target_param1: db_guid} = step)
       when is_integer(db_guid) and db_guid > 0 do
    case Mangos.Repo.get(Mangos.Creature, db_guid) do
      %Mangos.Creature{id: entry} -> %{step | buddy_guid: Guid.from_low_guid(:mob, entry, db_guid)}
      _ -> step
    end
  end

  defp resolve_buddy_guid(%ScriptStep{} = step), do: step

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
