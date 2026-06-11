defmodule ThistleTea.Game.Entity.Logic.QuestDialogStatus do
  @moduledoc """
  Computes the questgiver status icon and the gossip quest-menu entries for an
  NPC from its given/ended quest lists and the player's quest context.
  """
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements

  @none 0
  @unavailable 1
  @chat 2
  @incomplete 3
  @reward_rep 4
  @available 5
  @reward 7

  def none, do: @none
  def unavailable, do: @unavailable
  def chat, do: @chat
  def incomplete, do: @incomplete
  def reward_rep, do: @reward_rep
  def available, do: @available
  def reward, do: @reward

  def for_npc(giver_quests, ender_quests, ctx) do
    ender_statuses = Enum.map(ender_quests, &ender_status(&1, ctx))
    giver_statuses = Enum.map(giver_quests, &giver_status(&1, ctx))

    Enum.max(ender_statuses ++ giver_statuses, fn -> @none end)
  end

  def menu(giver_quests, ender_quests, ctx) do
    ender_entries =
      Enum.flat_map(ender_quests, fn quest ->
        case ender_status(quest, ctx) do
          @reward -> [{quest, @reward_rep}]
          @incomplete -> [{quest, @incomplete}]
          _status -> []
        end
      end)

    ender_ids = MapSet.new(ender_entries, fn {quest, _icon} -> quest.id end)

    giver_entries =
      Enum.flat_map(giver_quests, fn quest ->
        if not MapSet.member?(ender_ids, quest.id) and
             QuestRequirements.can_take?(quest, ctx) do
          [{quest, @available}]
        else
          []
        end
      end)

    ender_entries ++ giver_entries
  end

  defp ender_status(%Quest{} = quest, ctx) do
    case QuestLog.get(ctx.quest_log, quest.id) do
      %Entry{status: :complete} -> @reward
      %Entry{status: :incomplete} -> @incomplete
      _entry -> @none
    end
  end

  defp giver_status(%Quest{} = quest, ctx) do
    case QuestRequirements.can_take(quest, ctx) do
      :ok -> @available
      {:error, :low_level} -> @unavailable
      {:error, _reason} -> @none
    end
  end
end
