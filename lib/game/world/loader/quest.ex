defmodule ThistleTea.Game.World.Loader.Quest do
  @moduledoc """
  ETS cache of quest templates and questgiver/quest-ender relations from
  Mangos.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    rows = Mangos.Repo.all(Mangos.QuestTemplate)
    start_scripts = load_scripts(rows, :start_script, Mangos.QuestStartScript)
    complete_scripts = load_scripts(rows, :complete_script, Mangos.QuestEndScript)
    required_conditions = rows |> Enum.map(& &1.required_condition) |> ConditionLoader.load_by_ids()

    rows
    |> Enum.each(fn row ->
      quest = row |> Quest.build() |> attach_required_condition(required_conditions)

      quest = %{
        quest
        | start_script_steps: Map.get(start_scripts, quest.start_script_id, []),
          complete_script_steps: Map.get(complete_scripts, quest.complete_script_id, [])
      }

      :ets.insert(__MODULE__, {{:quest, quest.id}, quest})
    end)

    load_creature_relations(Mangos.CreatureQuestRelation, :giver)
    load_creature_relations(Mangos.CreatureInvolvedRelation, :ender)

    :ok
  end

  def attach_required_condition(%Quest{required_condition_id: 0} = quest, _conditions), do: quest

  def attach_required_condition(%Quest{required_condition_id: condition_id} = quest, conditions)
      when condition_id > 0 do
    condition = Map.get(conditions, condition_id, Condition.unresolved(condition_id))
    %{quest | required_condition: condition}
  end

  defp load_scripts(rows, field, schema) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&(&1 > 0))
    |> then(&Script.load_by_ids(schema, &1))
  end

  def get(quest_id) do
    case :ets.lookup(__MODULE__, {:quest, quest_id}) do
      [{_key, %Quest{} = quest}] -> quest
      _ -> nil
    end
  end

  def given_by(creature_entry), do: relation_lookup({:giver, creature_entry})

  def ended_by(creature_entry), do: relation_lookup({:ender, creature_entry})

  defp relation_lookup(key) do
    case :ets.lookup(__MODULE__, key) do
      [{_key, quest_ids}] -> quest_ids
      _ -> []
    end
  end

  defp load_creature_relations(schema, role) do
    schema
    |> Mangos.Repo.all()
    |> Enum.group_by(fn relation -> {role, relation.id} end, fn relation -> relation.quest end)
    |> Enum.each(fn {key, quest_ids} ->
      :ets.insert(__MODULE__, {key, Enum.sort(quest_ids)})
    end)
  end
end
