defmodule ThistleTea.Game.Entity.Logic.QuestLogTest do
  use ExUnit.Case, async: true

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
