defmodule ThistleTea.Game.Entity.Logic.QuestDialogStatusTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog

  defp ctx(overrides \\ []) do
    Enum.into(overrides, %{
      level: 10,
      race: 1,
      class: 1,
      quest_log: %{},
      rewarded_quests: MapSet.new()
    })
  end

  describe "for_npc/3" do
    test "none when the npc has no quests" do
      assert QuestDialogStatus.for_npc([], [], ctx()) == QuestDialogStatus.none()
    end

    test "available when a giver quest passes requirements" do
      quests = [%Quest{id: 1, min_level: 5}]
      assert QuestDialogStatus.for_npc(quests, [], ctx()) == QuestDialogStatus.available()
    end

    test "unavailable when the player is only too low level" do
      quests = [%Quest{id: 1, min_level: 50}]
      assert QuestDialogStatus.for_npc(quests, [], ctx()) == QuestDialogStatus.unavailable()
    end

    test "none when the quest is already rewarded" do
      quests = [%Quest{id: 1}]
      context = ctx(rewarded_quests: MapSet.new([1]))
      assert QuestDialogStatus.for_npc(quests, [], context) == QuestDialogStatus.none()
    end

    test "incomplete for an ender with the quest in progress" do
      {:ok, quest_log} = QuestLog.add(%{}, 1)
      quests = [%Quest{id: 1}]
      context = ctx(quest_log: quest_log)
      assert QuestDialogStatus.for_npc([], quests, context) == QuestDialogStatus.incomplete()
    end

    test "reward for an ender with the quest complete" do
      {:ok, quest_log} = QuestLog.add(%{}, 1)
      {:ok, quest_log} = QuestLog.update(quest_log, 1, &%{&1 | status: :complete})
      quests = [%Quest{id: 1}]
      context = ctx(quest_log: quest_log)
      assert QuestDialogStatus.for_npc([], quests, context) == QuestDialogStatus.reward()
    end
  end

  describe "menu/3" do
    test "lists takeable giver quests as available" do
      quests = [%Quest{id: 1, min_level: 5}, %Quest{id: 2, min_level: 50}]

      assert [{%Quest{id: 1}, icon}] = QuestDialogStatus.menu(quests, [], ctx())
      assert icon == QuestDialogStatus.available()
    end

    test "ender entries take precedence over giver entries for the same quest" do
      {:ok, quest_log} = QuestLog.add(%{}, 1)
      {:ok, quest_log} = QuestLog.update(quest_log, 1, &%{&1 | status: :complete})
      quest = %Quest{id: 1}
      context = ctx(quest_log: quest_log)

      assert [{%Quest{id: 1}, icon}] = QuestDialogStatus.menu([quest], [quest], context)
      assert icon == QuestDialogStatus.reward_rep()
    end

    test "in-progress quests show for enders, not givers" do
      {:ok, quest_log} = QuestLog.add(%{}, 1)
      quest = %Quest{id: 1}
      context = ctx(quest_log: quest_log)

      assert QuestDialogStatus.menu([quest], [], context) == []

      assert [{%Quest{id: 1}, icon}] = QuestDialogStatus.menu([], [quest], context)
      assert icon == QuestDialogStatus.incomplete()
    end
  end
end
