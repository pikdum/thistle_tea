defmodule ThistleTea.Game.Core.Profession.Professions do
  @moduledoc """
  Plans skill and related quest removal in one inventory transaction.
  Source items include bank storage and are consumed without restoring quest
  starters. No progress changes until the entire plan succeeds.
  """

  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.ChangeSet
  alias ThistleTea.Game.Core.Quest.QuestItems
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.Skills

  def plan(%Player{} = player, skill_id, quests, get_item) do
    if Skills.known?(player.skills, skill_id) do
      plan_removal(player, skill_id, quests, get_item)
    else
      {:error, :unknown_skill}
    end
  end

  defp plan_removal(player, skill_id, quests, get_item) do
    quests = Enum.filter(quests, &(&1.required_skill == skill_id))
    active = Enum.filter(quests, &QuestLog.active?(player.quest_log, &1.id))
    batch = QuestItems.remove_sources(player, active, get_item)

    with {:ok, changes} <- Inventory.plan(batch, get_item) do
      player = changes.player
      quest_ids = Enum.map(quests, & &1.id)

      quest_log =
        Enum.reduce(active, player.quest_log, fn quest, log ->
          {:ok, log} = QuestLog.remove(log, quest.id)
          log
        end)

      player = %{
        player
        | skills: Map.delete(player.skills, skill_id),
          quest_log: quest_log,
          rewarded_quests: MapSet.difference(player.rewarded_quests, MapSet.new(quest_ids))
      }

      {:ok, ChangeSet.put_player(changes, player)}
    end
  end
end
