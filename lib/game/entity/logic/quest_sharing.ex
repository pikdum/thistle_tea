defmodule ThistleTea.Game.Entity.Logic.QuestSharing do
  @moduledoc """
  Pure quest-sharing eligibility, recipient feedback, and shared timer inheritance.
  """

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements

  defmodule Offer do
    @moduledoc false
    defstruct [:sharer_guid, :sharer_pid, :quest_id, :group_id, mode: :manual]
  end

  def shareable?(%Quest{} = quest, quest_log, now_ms) do
    Quest.shareable?(quest) and current?(quest_log, quest.id, now_ms)
  end

  def current?(quest_log, quest_id, now_ms) do
    case QuestLog.get(quest_log, quest_id) do
      %Entry{status: status, expires_at_ms: deadline} when status in [:incomplete, :complete] ->
        is_nil(deadline) or deadline > now_ms

      _entry ->
        false
    end
  end

  def offer_result(%Quest{} = quest, context, condition_result, near?, busy?) do
    cond do
      not near? -> :too_far
      match?(%Entry{status: :complete}, QuestLog.get(context.quest_log, quest.id)) -> :finished
      QuestLog.active?(context.quest_log, quest.id) -> :have_quest
      QuestRequirements.base_can_take(quest, context) == {:error, :already_rewarded} -> :have_quest
      QuestRequirements.can_take(quest, context, condition_result) != :ok -> :cannot_take
      QuestLog.full?(context.quest_log) -> :log_full
      busy? -> :busy
      true -> :ok
    end
  end

  def inherit_timer(quest_log, quest_id, %Entry{expires_at_ms: deadline, client_expires_at: client_deadline})
      when is_integer(deadline) do
    QuestLog.update(quest_log, quest_id, fn entry ->
      %{entry | expires_at_ms: deadline, client_expires_at: client_deadline}
    end)
  end

  def inherit_timer(quest_log, _quest_id, _source_entry), do: {:ok, quest_log}
end
