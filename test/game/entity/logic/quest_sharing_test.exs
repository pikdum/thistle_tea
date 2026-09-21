defmodule ThistleTea.Game.Entity.Logic.QuestSharingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestSharing

  setup [:quest_context]

  describe "shareable?/3" do
    test "requires the flag and a current unexpired quest", %{quest: quest} do
      log = %{0 => %Entry{quest_id: quest.id}}
      assert QuestSharing.shareable?(quest, log, 1_000)
      refute QuestSharing.shareable?(%{quest | flags: 0}, log, 1_000)
      refute QuestSharing.shareable?(quest, %{}, 1_000)
      assert QuestSharing.shareable?(quest, %{0 => %{log[0] | status: :complete}}, 1_000)
      refute QuestSharing.shareable?(quest, %{0 => %{log[0] | status: :failed}}, 1_000)
      refute QuestSharing.shareable?(quest, %{0 => %{log[0] | expires_at_ms: 1_000}}, 1_000)
    end
  end

  describe "offer_result/5" do
    test "orders range, quest status, eligibility, capacity, and busy feedback", %{quest: quest, context: context} do
      assert QuestSharing.offer_result(quest, context, :met, true, false) == :ok
      assert QuestSharing.offer_result(quest, context, :met, false, true) == :too_far
      active = %{context | quest_log: %{0 => %Entry{quest_id: quest.id}}}
      assert QuestSharing.offer_result(quest, active, :met, true, true) == :have_quest
      complete = %{context | quest_log: %{0 => %Entry{quest_id: quest.id, status: :complete}}}
      assert QuestSharing.offer_result(quest, complete, :met, true, true) == :finished
      rewarded = %{context | rewarded_quests: MapSet.new([quest.id])}
      assert QuestSharing.offer_result(quest, rewarded, :met, true, true) == :have_quest
      assert QuestSharing.offer_result(quest, %{context | level: 1}, :met, true, true) == :cannot_take
      assert QuestSharing.offer_result(quest, context, :unmet, true, false) == :cannot_take
      full = %{context | quest_log: Map.new(0..19, &{&1, %Entry{quest_id: &1 + 100}})}
      assert QuestSharing.offer_result(quest, full, :met, true, true) == :log_full
      assert QuestSharing.offer_result(quest, context, :met, true, true) == :busy
    end

    test "allows rewarded repeatable quests but enforces prerequisites and existing timers", %{
      quest: quest,
      context: context
    } do
      rewarded = %{context | rewarded_quests: MapSet.new([quest.id])}
      assert QuestSharing.offer_result(%{quest | special_flags: 1}, rewarded, :met, true, false) == :ok
      assert QuestSharing.offer_result(%{quest | prev_quest_id: 2}, context, :met, true, false) == :cannot_take
      timed = %{context | quest_log: %{0 => %Entry{quest_id: 2, expires_at_ms: 10_000}}}
      assert QuestSharing.offer_result(%{quest | limit_time: 60}, timed, :met, true, false) == :cannot_take
    end
  end

  describe "inherit_timer/3" do
    test "copies the remaining deadline without copying objective progress", %{quest: quest} do
      {:ok, log} = QuestLog.add(%{}, %{quest | limit_time: 60}, 30_000, 1_000)
      source = %Entry{quest_id: quest.id, expires_at_ms: 45_000, client_expires_at: 1_015, counts: %{0 => 3}}
      assert {:ok, inherited} = QuestSharing.inherit_timer(log, quest.id, source)
      assert QuestLog.get(inherited, quest.id).expires_at_ms == 45_000
      assert QuestLog.get(inherited, quest.id).client_expires_at == 1_015
      assert QuestLog.get(inherited, quest.id).counts == %{}
      assert QuestSharing.inherit_timer(log, quest.id, nil) == {:ok, log}
    end
  end

  defp quest_context(_context) do
    %{
      quest: %Quest{id: 1, flags: 8, min_level: 10},
      context: %{level: 50, race: 1, class: 1, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %{}}
    }
  end
end
