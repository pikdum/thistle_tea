defmodule ThistleTea.Game.Entity.Logic.QuestRequirementsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestRequirements

  defp ctx(overrides \\ []) do
    Enum.into(overrides, %{
      level: 10,
      race: 1,
      class: 1,
      quest_log: %{},
      rewarded_quests: MapSet.new()
    })
  end

  describe "can_take/2" do
    test "passes a plain quest" do
      assert QuestRequirements.can_take(%Quest{id: 1}, ctx()) == :ok
    end

    test "rejects active quests" do
      {:ok, quest_log} = QuestLog.add(%{}, 1)

      assert QuestRequirements.can_take(%Quest{id: 1}, ctx(quest_log: quest_log)) ==
               {:error, :already_active}
    end

    test "rejects rewarded quests unless repeatable" do
      context = ctx(rewarded_quests: MapSet.new([1]))

      assert QuestRequirements.can_take(%Quest{id: 1}, context) == {:error, :already_rewarded}
      assert QuestRequirements.can_take(%Quest{id: 1, special_flags: 1}, context) == :ok
    end

    test "rejects timed quests" do
      assert QuestRequirements.can_take(%Quest{id: 1, limit_time: 600}, ctx()) ==
               {:error, :timed_unsupported}
    end

    test "checks the race mask" do
      orc_only = %Quest{id: 1, required_races: 2}

      assert QuestRequirements.can_take(orc_only, ctx(race: 2)) == :ok
      assert QuestRequirements.can_take(orc_only, ctx(race: 1)) == {:error, :wrong_race}
    end

    test "checks the class mask" do
      warlock_only = %Quest{id: 1, required_classes: 256}

      assert QuestRequirements.can_take(warlock_only, ctx(class: 9)) == :ok
      assert QuestRequirements.can_take(warlock_only, ctx(class: 1)) == {:error, :wrong_class}
    end

    test "checks minimum level" do
      quest = %Quest{id: 1, min_level: 11}

      assert QuestRequirements.can_take(quest, ctx(level: 11)) == :ok
      assert QuestRequirements.can_take(quest, ctx(level: 10)) == {:error, :low_level}
    end

    test "requires the previous quest to be rewarded" do
      quest = %Quest{id: 2, prev_quest_id: 1}

      assert QuestRequirements.can_take(quest, ctx()) == {:error, :missing_prerequisite}
      assert QuestRequirements.can_take(quest, ctx(rewarded_quests: MapSet.new([1]))) == :ok
    end
  end
end
