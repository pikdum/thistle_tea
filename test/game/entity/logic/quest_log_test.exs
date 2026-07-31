defmodule ThistleTea.Game.Entity.Logic.QuestLogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry

  describe "add/2" do
    test "assigns the lowest free slot" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)
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

  describe "add/4" do
    test "records monotonic and client deadlines for timed quests" do
      quest = %Quest{id: 33, limit_time: 600}

      {:ok, quest_log} = QuestLog.add(%{}, quest, 10_000, 1_700_000_000)

      assert %Entry{
               expires_at_ms: 610_000,
               client_expires_at: 1_700_000_600
             } = QuestLog.get(quest_log, quest.id)

      assert <<33::little-size(32), 0::little-size(32), 1_700_000_600::little-size(32)>> =
               QuestLog.slot_binary(QuestLog.get(quest_log, quest.id))
    end

    test "leaves ordinary quests without deadlines" do
      {:ok, quest_log} = QuestLog.add(%{}, %Quest{id: 33}, 10_000, 1_700_000_000)

      assert %Entry{expires_at_ms: nil, client_expires_at: nil} = QuestLog.get(quest_log, 33)
    end
  end

  describe "fail_timed/3" do
    test "fails active quests at their deadline" do
      {:ok, quest_log} = QuestLog.add(%{}, %Quest{id: 33, limit_time: 60}, 10_000, 1_700_000_000)

      assert QuestLog.fail_timed(quest_log, 33, 69_999) == {:error, :not_expired}
      assert {:ok, quest_log} = QuestLog.fail_timed(quest_log, 33, 70_000)

      assert %Entry{
               status: :failed,
               expires_at_ms: nil,
               client_expires_at: 1
             } = QuestLog.get(quest_log, 33)
    end

    test "recognizes the active timer" do
      refute QuestLog.timed?(%{})
      {:ok, quest_log} = QuestLog.add(%{}, %Quest{id: 33, limit_time: 60}, 10_000, 1_700_000_000)
      assert QuestLog.timed?(quest_log)
      assert [%Entry{quest_id: 33}] = QuestLog.timed_entries(quest_log)
    end
  end

  describe "fail/2" do
    test "fails an ordinary active quest" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)

      assert {:ok, quest_log, false} = QuestLog.fail(quest_log, 33)
      assert %Entry{status: :failed, expires_at_ms: nil, client_expires_at: 1} = QuestLog.get(quest_log, 33)
    end

    test "reports when the failed quest had a timer" do
      {:ok, quest_log} = QuestLog.add(%{}, %Quest{id: 33, limit_time: 60}, 10_000, 1_700_000_000)

      assert {:ok, quest_log, true} = QuestLog.fail(quest_log, 33)
      assert %Entry{status: :failed, expires_at_ms: nil, client_expires_at: 1} = QuestLog.get(quest_log, 33)
    end

    test "rejects missing and already failed quests" do
      assert QuestLog.fail(%{}, 33) == {:error, :not_active}
      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {:ok, quest_log, false} = QuestLog.fail(quest_log, 33)
      assert QuestLog.fail(quest_log, 33) == {:error, :already_failed}
    end

    test "does not regress a completed quest" do
      {:ok, quest_log} = QuestLog.add(%{}, 33)
      {:ok, quest_log} = QuestLog.update(quest_log, 33, &%{&1 | status: :complete})

      assert QuestLog.fail(quest_log, 33) == {:error, :not_incomplete}
      assert %Entry{status: :complete} = QuestLog.get(quest_log, 33)
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

  describe "increment_interaction/4" do
    test "credits only matching non-spell gameobject objectives" do
      quest = %Quest{
        id: 33,
        required_entity_objectives: [
          {0, :game_object, 3189, 0, 1},
          {1, :game_object, 1721, 3366, 1}
        ]
      }

      {:ok, quest_log} = QuestLog.add(%{}, quest.id)

      assert {:ok, quest_log, %{index: 0, count: 1}} =
               QuestLog.increment_interaction(quest_log, quest, :game_object, 3189)

      assert QuestLog.increment_interaction(quest_log, quest, :game_object, 1721) == :no_credit
      assert QuestLog.increment_interaction(quest_log, quest, :creature, 3189) == :no_credit
    end
  end

  describe "increment_cast/5" do
    test "matches the target type, entry, and spell" do
      quest = %Quest{
        id: 33,
        required_entity_objectives: [
          {0, :creature, 10_978, 17_166, 1},
          {1, :game_object, 176_158, 17_155, 1}
        ]
      }

      {:ok, quest_log} = QuestLog.add(%{}, quest.id)

      assert {:ok, quest_log, %{index: 0, count: 1}} =
               QuestLog.increment_cast(quest_log, quest, :creature, 10_978, 17_166)

      assert {:ok, _quest_log, %{index: 1, count: 1}} =
               QuestLog.increment_cast(quest_log, quest, :game_object, 176_158, 17_155)

      assert QuestLog.increment_cast(quest_log, quest, :creature, 10_978, 17_155) == :no_credit
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

    test "exploration quests stay incomplete until explored" do
      quest = %Quest{id: 62, special_flags: 2}
      {:ok, quest_log} = QuestLog.add(%{}, 62)

      assert {^quest_log, :unchanged} = QuestLog.evaluate(quest_log, quest, fn _id -> 0 end)
      assert %Entry{status: :incomplete} = QuestLog.get(quest_log, 62)

      {:ok, quest_log} = QuestLog.mark_explored(quest_log, 62)

      assert {quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn _id -> 0 end)
      assert %Entry{status: :complete, explored?: true} = QuestLog.get(quest_log, 62)
    end

    test "exploration quests with item objectives need both" do
      quest = %Quest{id: 62, special_flags: 2, required_items: [{0, 750, 2}]}
      {:ok, quest_log} = QuestLog.add(%{}, 62)
      {:ok, quest_log} = QuestLog.mark_explored(quest_log, 62)

      assert {^quest_log, :unchanged} = QuestLog.evaluate(quest_log, quest, fn 750 -> 1 end)
      assert {_quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn 750 -> 2 end)
    end

    test "entity objectives share the client counter slots" do
      quest = %Quest{
        id: 62,
        required_entity_objectives: [
          {0, :creature, 10_978, 17_166, 1},
          {2, :game_object, 176_158, 0, 1}
        ]
      }

      {:ok, quest_log} = QuestLog.add(%{}, quest.id)
      {:ok, quest_log, _credit} = QuestLog.increment_cast(quest_log, quest, :creature, 10_978, 17_166)
      assert {^quest_log, :unchanged} = QuestLog.evaluate(quest_log, quest, fn _item_id -> 0 end)

      {:ok, quest_log, _credit} = QuestLog.increment_interaction(quest_log, quest, :game_object, 176_158)
      assert {quest_log, :completed} = QuestLog.evaluate(quest_log, quest, fn _item_id -> 0 end)
      assert %Entry{counts: %{0 => 1, 2 => 1}} = QuestLog.get(quest_log, quest.id)
    end

    test "reputation objectives complete and regress with standing" do
      quest = %Quest{id: 62, reputation_objective_faction: 529, reputation_objective_value: 3_000}
      {:ok, quest_log} = QuestLog.add(%{}, 62)

      assert {^quest_log, :unchanged} =
               QuestLog.evaluate(quest_log, quest, fn _item_id -> 0 end, fn 529 -> 2_999 end)

      assert {quest_log, :completed} =
               QuestLog.evaluate(quest_log, quest, fn _item_id -> 0 end, fn 529 -> 3_000 end)

      assert {_quest_log, :incompleted} =
               QuestLog.evaluate(quest_log, quest, fn _item_id -> 0 end, fn 529 -> 2_999 end)
    end
  end

  describe "mark_explored/2" do
    test "errors for missing or already-explored quests" do
      assert QuestLog.mark_explored(%{}, 62) == {:error, :not_active}

      {:ok, quest_log} = QuestLog.add(%{}, 62)
      {:ok, quest_log} = QuestLog.mark_explored(quest_log, 62)

      assert QuestLog.mark_explored(quest_log, 62) == {:error, :no_change}
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

    test "failed timed quest leaves the timer sentinel" do
      failed = %Entry{quest_id: 33, status: :failed, client_expires_at: 1}

      assert <<33::little-size(32), 0, 0, 0, 2, 1::little-size(32)>> =
               QuestLog.slot_binary(failed)
    end
  end
end
