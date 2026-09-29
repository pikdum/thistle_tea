defmodule ThistleTea.Game.World.Inbound.Quest do
  @moduledoc "Handles decoded quest giver and quest log client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.QuestSharing
  alias ThistleTea.Game.World.Outbound

  def messages do
    [
      Message.CmsgPushquesttoparty,
      Message.CmsgQuestConfirmAccept,
      Message.CmsgQuestgiverAcceptQuest,
      Message.CmsgQuestgiverCancel,
      Message.CmsgQuestgiverChooseReward,
      Message.CmsgQuestgiverCompleteQuest,
      Message.CmsgQuestgiverHello,
      Message.CmsgQuestgiverQueryQuest,
      Message.CmsgQuestgiverRequestReward,
      Message.CmsgQuestgiverStatusQuery,
      Message.CmsgQuestlogRemoveQuest,
      Message.MsgQuestPushResultClient
    ]
  end

  def handle(%Message.CmsgPushquesttoparty{quest_id: quest_id}, state), do: QuestSharing.share(state, quest_id)

  def handle(%Message.CmsgQuestConfirmAccept{quest_id: quest_id}, state), do: QuestSharing.confirm(state, quest_id)

  def handle(
        %Message.CmsgQuestgiverAcceptQuest{guid: guid, quest_id: quest_id},
        %{ready: true, character: %Character{}} = state
      ) do
    Quests.accept(state, guid, quest_id)
  end

  def handle(%Message.CmsgQuestgiverAcceptQuest{}, state), do: state

  def handle(%Message.CmsgQuestgiverCancel{}, %{ready: true, character: %Character{}} = state),
    do: Quests.cancel_dialog(state)

  def handle(%Message.CmsgQuestgiverCancel{}, state), do: state

  def handle(%Message.CmsgQuestgiverChooseReward{} = message, %{ready: true, character: %Character{}} = state) do
    Quests.choose_reward(state, message.guid, message.quest_id, message.reward_index)
  end

  def handle(%Message.CmsgQuestgiverChooseReward{}, state), do: state

  def handle(
        %Message.CmsgQuestgiverCompleteQuest{guid: guid, quest_id: quest_id},
        %{ready: true, character: %Character{}} = state
      ) do
    Quests.complete_quest(state, guid, quest_id)
  end

  def handle(%Message.CmsgQuestgiverCompleteQuest{}, state), do: state

  def handle(%Message.CmsgQuestgiverHello{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Quests.hello(state, guid)
  end

  def handle(%Message.CmsgQuestgiverHello{}, state), do: state

  def handle(
        %Message.CmsgQuestgiverQueryQuest{guid: guid, quest_id: quest_id},
        %{ready: true, character: %Character{}} = state
      ) do
    Quests.query_quest(state, guid, quest_id)
  end

  def handle(%Message.CmsgQuestgiverQueryQuest{}, state), do: state

  def handle(
        %Message.CmsgQuestgiverRequestReward{guid: guid, quest_id: quest_id},
        %{ready: true, character: %Character{}} = state
      ) do
    Quests.request_reward(state, guid, quest_id)
  end

  def handle(%Message.CmsgQuestgiverRequestReward{}, state), do: state

  def handle(%Message.CmsgQuestgiverStatusQuery{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    Outbound.send_packet(%Message.SmsgQuestgiverStatus{
      guid: guid,
      status: Quests.dialog_status(guid, c)
    })

    state
  end

  def handle(%Message.CmsgQuestgiverStatusQuery{}, state), do: state

  def handle(%Message.CmsgQuestlogRemoveQuest{slot: slot}, %{ready: true, character: %Character{}} = state) do
    Quests.abandon(state, slot)
  end

  def handle(%Message.CmsgQuestlogRemoveQuest{}, state), do: state

  def handle(%Message.MsgQuestPushResultClient{result: result}, state), do: QuestSharing.result(state, result)
end
