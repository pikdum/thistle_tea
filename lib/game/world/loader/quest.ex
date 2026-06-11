defmodule ThistleTea.Game.World.Loader.Quest do
  @moduledoc """
  ETS cache of quest templates and questgiver/quest-ender relations from
  Mangos.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Quest

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.QuestTemplate
    |> Mangos.Repo.all()
    |> Enum.each(fn row ->
      quest = Quest.build(row)
      :ets.insert(__MODULE__, {{:quest, quest.id}, quest})
    end)

    from(qr in Mangos.QuestRelation, where: qr.actor == ^Mangos.QuestRelation.actor_creature())
    |> Mangos.Repo.all()
    |> Enum.group_by(fn qr -> {relation_key(qr.role), qr.entry} end, fn qr -> qr.quest end)
    |> Enum.each(fn {key, quest_ids} ->
      :ets.insert(__MODULE__, {key, Enum.sort(quest_ids)})
    end)

    :ok
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

  defp relation_key(0), do: :giver
  defp relation_key(_role), do: :ender
end
