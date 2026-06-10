defmodule ThistleTea.Game.Entity.Logic.QuestLogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry

  describe "add/2" do
    test "assigns the lowest free slot" do
      {:ok, quest_log} = QuestLog.add(nil, 33)
      assert %Entry{quest_id: 33, status: :incomplete} = quest_log[0]

      {:ok, quest_log} = QuestLog.add(quest_log, 62)
      assert %Entry{quest_id: 62} = quest_log[1]
    end

    test "reuses cleared slots" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {:ok, quest_log} = QuestLog.add(quest_log, 62)
      {:ok, quest_log} = QuestLog.remove(quest_log, 33)

      assert quest_log[0] == :empty

      {:ok, quest_log} = QuestLog.add(quest_log, 76)
      assert %Entry{quest_id: 76} = quest_log[0]
    end

    test "rejects duplicates" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)
      assert QuestLog.add(quest_log, 33) == {:error, :already_active}
    end

    test "rejects when all slots are taken" do
      quest_log =
        Enum.reduce(1..20, %{}, fn quest_id, acc ->
          {:ok, acc} = QuestLog.add(acc, quest_id)
          acc
        end)

      assert QuestLog.full?(quest_log)
      assert QuestLog.add(quest_log, 99) == {:error, :log_full}
    end
  end

  describe "remove/2" do
    test "leaves an empty tombstone" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {:ok, quest_log} = QuestLog.remove(quest_log, 33)

      assert quest_log[0] == :empty
      refute QuestLog.active?(quest_log, 33)
    end

    test "errors when quest is not active" do
      assert QuestLog.remove(%{}, 33) == {:error, :not_active}
    end
  end

  describe "increment_kill/3" do
    setup do
      quest = %Quest{
        id: 33,
        required_kills: [{0, 299, 2}, {2, 300, 1}]
      }

      {:ok, quest_log} = QuestLog.add(%{}, 33)
      %{quest: quest, quest_log: quest_log}
    end

    test "credits a matching kill into the right objective slot", %{quest: quest, quest_log: quest_log} do
      assert {:ok, quest_log, %{index: 0, count: 1, required: 2}} =
               QuestLog.increment_kill(quest_log, quest, 299)

      assert {:ok, _quest_log, %{index: 2, count: 1, required: 1}} =
               QuestLog.increment_kill(quest_log, quest, 300)
    end

    test "caps at the required count", %{quest: quest, quest_log: quest_log} do
      {:ok, quest_log, _credit} = QuestLog.increment_kill(quest_log, quest, 299)
      {:ok, quest_log, %{count: 2}} = QuestLog.increment_kill(quest_log, quest, 299)

      assert QuestLog.increment_kill(quest_log, quest, 299) == :no_credit
    end

    test "ignores non-objective creatures", %{quest: quest, quest_log: quest_log} do
      assert QuestLog.increment_kill(quest_log, quest, 999) == :no_credit
    end

    test "ignores quests not in the log", %{quest: quest} do
      assert QuestLog.increment_kill(%{}, quest, 299) == :no_credit
    end

    test "ignores completed quests", %{quest: quest, quest_log: quest_log} do
      {:ok, quest_log} = QuestLog.update(quest_log, 33, &%{&1 | status: :complete})
      assert QuestLog.increment_kill(quest_log, quest, 299) == :no_credit
    end
  end

  describe "evaluate/3" do
    test "completes when kills and items are satisfied" do
      quest = %Quest{
        id: 33,
        required_kills: [{0, 299, 1}],
        required_items: [{0, 750, 2}]
      }

      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {:ok, quest_log, _credit} = QuestLog.increment_kill(quest_log, quest, 299)

      assert {^quest_log, :unchanged} = QuestLog.evaluate(quest_log, quest, fn 750 -> 1 end)

      assert {quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn 750 -> 2 end)
      assert %Entry{status: :complete} = QuestLog.get(quest_log, 33)

      assert {^quest_log, :unchanged} = QuestLog.evaluate(quest_log, quest, fn 750 -> 5 end)
    end

    test "regresses to incomplete when items are lost" do
      quest = %Quest{id: 33, required_items: [{0, 750, 2}]}

      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn 750 -> 2 end)

      assert {quest_log, :incompleted} = QuestLog.evaluate(quest_log, quest, fn 750 -> 1 end)
      assert %Entry{status: :incomplete} = QuestLog.get(quest_log, 33)
    end

    test "objective-less quests complete immediately" do
      quest = %Quest{id: 33}
      {:ok, quest_log} = QuestLog.add(%{}, 33)

      assert {_quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn _id -> 0 end)
    end
  end

  describe "slot_binary/1" do
    test "never-used slot serializes to nil" do
      assert QuestLog.slot_binary(nil) == nil
    end

    test "cleared slot serializes to twelve zero bytes" do
      assert QuestLog.slot_binary(:empty) == <<0::size(96)>>
    end

    test "incomplete quest with no counters" do
      entry = %Entry{quest_id: 783}

      assert QuestLog.slot_binary(entry) ==
               <<783::little-size(32), 0::little-size(32), 0::little-size(32)>>
    end

    test "packs counters six bits per objective" do
      entry = %Entry{quest_id: 33, counts: %{0 => 3, 1 => 1, 2 => 63, 3 => 2}}

      expected_word =
        3 +
          Bitwise.bsl(1, 6) +
          Bitwise.bsl(63, 12) +
          Bitwise.bsl(2, 18)

      assert QuestLog.slot_binary(entry) ==
               <<33::little-size(32), expected_word::little-size(32), 0::little-size(32)>>
    end

    test "caps counters at 63" do
      entry = %Entry{quest_id: 33, counts: %{0 => 100}}

      assert QuestLog.slot_binary(entry) ==
               <<33::little-size(32), 63::little-size(32), 0::little-size(32)>>
    end

    test "sets the state byte for complete and failed" do
      complete = %Entry{quest_id: 33, status: :complete}
      failed = %Entry{quest_id: 33, status: :failed}

      assert <<33::little-size(32), 0, 0, 0, 1, 0::little-size(32)>> =
               QuestLog.slot_binary(complete)

      assert <<33::little-size(32), 0, 0, 0, 2, 0::little-size(32)>> =
               QuestLog.slot_binary(failed)
    end
  end
end
