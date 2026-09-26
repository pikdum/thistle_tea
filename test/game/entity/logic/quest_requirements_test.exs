defmodule ThistleTea.Game.Entity.Logic.QuestRequirementsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Condition.Reason
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestRequirements

  defp ctx(overrides \\ []) do
    Enum.into(overrides, %{
      level: 10,
      race: 1,
      class: 1,
      quest_log: %{},
      rewarded_quests: MapSet.new(),
      reputation: %{}
    })
  end

  describe "can_auto_reward?/2" do
    test "uses flag-quest requirements without requiring a free log slot or reputation" do
      quest = %Quest{
        id: 50,
        flags: 0x400,
        min_level: 10,
        required_min_reputation_faction: 1,
        required_min_reputation_value: 42_000
      }

      full = Map.new(0..19, &{&1, %QuestLog.Entry{quest_id: &1 + 1}})
      assert QuestRequirements.can_auto_reward?(quest, ctx(quest_log: full))
      refute QuestRequirements.can_auto_reward?(%{quest | flags: 0}, ctx())
      refute QuestRequirements.can_auto_reward?(quest, ctx(level: 9))
      refute QuestRequirements.can_auto_reward?(quest, ctx(rewarded_quests: MapSet.new([50])))
    end

    test "checks class race skill and signed prerequisites" do
      quest = %Quest{id: 50, flags: 0x400}
      refute QuestRequirements.can_auto_reward?(%{quest | required_races: 2}, ctx())
      refute QuestRequirements.can_auto_reward?(%{quest | required_classes: 2}, ctx())
      refute QuestRequirements.can_auto_reward?(%{quest | required_skill: 185, required_skill_value: 1}, ctx())
      refute QuestRequirements.can_auto_reward?(%{quest | prev_quest_id: 49}, ctx())
      assert QuestRequirements.can_auto_reward?(%{quest | prev_quest_id: 49}, ctx(rewarded_quests: MapSet.new([49])))
      {:ok, log} = QuestLog.add(%{}, 49)
      assert QuestRequirements.can_auto_reward?(%{quest | prev_quest_id: -49}, ctx(quest_log: log))
    end
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

    test "allows one timed quest at a time" do
      timed = %Quest{id: 1, limit_time: 600}
      assert QuestRequirements.can_take(timed, ctx()) == :ok

      {:ok, quest_log} = QuestLog.add(%{}, %Quest{id: 2, limit_time: 60}, 10_000, 1_700_000_000)

      assert QuestRequirements.can_take(timed, ctx(quest_log: quest_log)) ==
               {:error, :timed_quest_active}
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

    test "checks minimum and exclusive maximum reputation bounds" do
      quest = %Quest{
        id: 1,
        required_min_reputation_faction: 529,
        required_min_reputation_value: 3_000,
        required_max_reputation_faction: 87,
        required_max_reputation_value: 0
      }

      assert QuestRequirements.can_take(quest, ctx(reputation: %{529 => 2_999, 87 => -1})) ==
               {:error, :low_reputation}

      assert QuestRequirements.can_take(quest, ctx(reputation: %{529 => 3_000, 87 => 0})) ==
               {:error, :high_reputation}

      assert QuestRequirements.can_take(quest, ctx(reputation: %{529 => 3_000, 87 => -1})) == :ok
    end
  end

  describe "can_take/3" do
    test "treats unconditioned and met conditioned quests as takeable" do
      assert QuestRequirements.can_take(%Quest{id: 1}, ctx()) == :ok

      assert QuestRequirements.can_take(%Quest{id: 2, required_condition_id: 42}, ctx(), :met) ==
               :ok
    end

    test "denies unmet conditions before structural requirements" do
      quest = %Quest{id: 1, min_level: 50, required_condition_id: 42}

      assert QuestRequirements.can_take(quest, ctx(), :unmet) == {:error, :required_condition}
    end

    test "denies unknown conditions while preserving reasons" do
      reasons = [%Reason{entry: 42, type: :instance_data, capability: {:unsupported_capability, :instance_data}}]

      assert QuestRequirements.can_take(%Quest{id: 1, required_condition_id: 42}, ctx(), {:unknown, reasons}) ==
               {:error, {:required_condition_unknown, reasons}}
    end

    test "missing conditioned results remain explicitly unknown" do
      quest = %Quest{id: 1, required_condition_id: 42}

      assert {:error, {:required_condition_unknown, [%Reason{entry: 42, capability: :condition_result_missing}]}} =
               QuestRequirements.can_take(quest, ctx())
    end

    test "structural failures remain unchanged after a met condition" do
      quest = %Quest{id: 1, min_level: 11, required_condition_id: 42}

      assert QuestRequirements.can_take(quest, ctx(), :met) == {:error, :low_level}
    end
  end

  describe "base_can_take/2" do
    test "checks structural requirements without required conditions" do
      quest = %Quest{id: 1, required_condition_id: 42}

      assert QuestRequirements.base_can_take(quest, ctx()) == :ok
      assert QuestRequirements.base_can_take?(quest, ctx())
    end
  end
end
