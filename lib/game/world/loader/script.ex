defmodule ThistleTea.Game.World.Loader.Script do
  @moduledoc """
  Loads generic script-command rows (`creature_ai_scripts`,
  `creature_movement_scripts`, `generic_scripts`, …) into `ScriptStep`
  structs grouped by script id, resolving the broadcast texts referenced by
  talk steps and recursively resolving the `generic_scripts` referenced by
  start-script and summon steps (cycle-guarded), so the runtime interpreter
  never touches the database.
  """
  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep

  def load_by_ids(schema, script_ids), do: load_by_ids(schema, script_ids, MapSet.new())

  defp load_by_ids(_schema, [], _visited), do: %{}

  defp load_by_ids(schema, script_ids, visited) when is_list(script_ids) do
    script_ids
    |> Enum.uniq()
    |> schema.query()
    |> Mangos.Repo.all()
    |> Enum.map(&ScriptStep.build/1)
    |> resolve_texts()
    |> resolve_nested_scripts(visited)
    |> Enum.group_by(& &1.script_id)
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
