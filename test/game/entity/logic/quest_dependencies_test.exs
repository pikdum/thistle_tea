defmodule ThistleTea.Game.Entity.Logic.QuestDependenciesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestGraph
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements

  defp ctx(log \\ [], rewarded \\ []) do
    %{
      level: 60,
      race: 1,
      class: 1,
      quest_log:
        log |> Enum.with_index() |> Map.new(fn {{id, status}, slot} -> {slot, %Entry{quest_id: id, status: status}} end),
      rewarded_quests: MapSet.new(rewarded),
      reputation: %{},
      skills: %{},
      skill_bonuses: %{}
    }
  end

  defp compile(quests), do: quests |> QuestGraph.compile() |> Map.new(&{&1.id, &1})

  describe "can_take/2" do
    test "accepts any rewarded alternative and keeps negative prerequisites current" do
      quests =
        compile([
          %Quest{id: 1, next_quest_id: 4},
          %Quest{id: 2, next_quest_id: 4},
          %Quest{id: 3, next_quest_id: -4, special_flags: 1},
          %Quest{id: 4}
        ])

      assert QuestRequirements.can_take(quests[4], ctx()) == {:error, :missing_prerequisite}
      for id <- [1, 2], do: assert(QuestRequirements.can_take(quests[4], ctx([], [id])) == :ok)

      for status <- [:incomplete, :complete],
          do: assert(QuestRequirements.can_take(quests[4], ctx([{3, status}])) == :ok)

      assert QuestRequirements.can_take(quests[4], ctx([{3, :failed}])) == {:error, :missing_prerequisite}
      assert QuestRequirements.can_take(quests[4], ctx([], [3])) == {:error, :missing_prerequisite}
      assert QuestRequirements.can_take(quests[4], ctx([{3, :incomplete}], [3])) == :ok
      assert QuestRequirements.can_take(quests[4], ctx([{3, :complete}], [3])) == {:error, :missing_prerequisite}
    end

    test "requires every member of negative groups in the requested state" do
      quests =
        compile([
          %Quest{id: 1, exclusive_group: -1},
          %Quest{id: 2, exclusive_group: -1},
          %Quest{id: 3, prev_quest_id: 1},
          %Quest{id: 4, prev_quest_id: -1}
        ])

      assert QuestRequirements.can_take(quests[3], ctx([], [1])) == {:error, :missing_prerequisite}
      assert QuestRequirements.can_take(quests[3], ctx([], [1, 2])) == :ok
      assert QuestRequirements.can_take(quests[4], ctx([{1, :incomplete}, {2, :complete}])) == :ok

      assert QuestRequirements.can_take(quests[4], ctx([{1, :incomplete}, {2, :failed}])) ==
               {:error, :missing_prerequisite}

      assert QuestRequirements.can_take(quests[4], ctx([{1, :incomplete}], [2])) == {:error, :missing_prerequisite}
      assert QuestRequirements.can_take(quests[2], ctx([{1, :incomplete}])) == :ok
    end

    test "exclusive choices block active and permanent rewarded alternatives but allow failed or repeatable ones" do
      quests =
        compile([
          %Quest{id: 1, exclusive_group: 1},
          %Quest{id: 2, exclusive_group: 1},
          %Quest{id: 3, exclusive_group: 1, special_flags: 1}
        ])

      for status <- [:incomplete, :complete] do
        assert QuestRequirements.can_take(quests[1], ctx([{2, status}])) == {:error, :exclusive_quest}
        assert QuestRequirements.can_take(quests[1], ctx([{3, status}], [3])) == {:error, :exclusive_quest}
      end

      assert QuestRequirements.can_take(quests[1], ctx([], [2])) == {:error, :exclusive_quest}
      assert QuestRequirements.can_take(quests[1], ctx([{2, :failed}])) == :ok
      assert QuestRequirements.can_take(quests[1], ctx([], [3])) == :ok
    end

    test "chain links exclude current neighbors without requiring earlier rewards" do
      quests = compile([%Quest{id: 1, next_quest_in_chain: 2}, %Quest{id: 2, next_quest_in_chain: 3}, %Quest{id: 3}])
      assert QuestRequirements.can_take(quests[2], ctx()) == :ok
      assert QuestRequirements.can_take(quests[2], ctx([{1, :incomplete}])) == {:error, :previous_chain_active}
      assert QuestRequirements.can_take(quests[2], ctx([], [1])) == :ok
      assert QuestRequirements.can_take(quests[2], ctx([{1, :failed}])) == :ok
      assert QuestRequirements.can_take(quests[2], ctx([{3, :complete}])) == {:error, :next_chain_active}
      assert QuestRequirements.can_take(quests[2], ctx([], [3])) == {:error, :next_chain_active}
      assert QuestRequirements.can_take(quests[2], ctx([{3, :failed}])) == :ok
    end

    test "breadcrumbs require every target and block targets until resolved or abandoned" do
      quests =
        compile([
          %Quest{id: 1, breadcrumb_for_quest_id: 2},
          %Quest{id: 2, breadcrumb_for_quest_id: 3},
          %Quest{id: 3, min_level: 40}
        ])

      assert QuestRequirements.can_take(quests[1], %{ctx() | level: 39}) == {:error, :breadcrumb_unavailable}
      assert QuestRequirements.can_take(quests[1], ctx()) == :ok

      for id <- [2, 3], status <- [:incomplete, :complete, :failed] do
        assert QuestRequirements.can_take(quests[id], ctx([{1, status}])) == {:error, :breadcrumb_active}
      end

      assert QuestRequirements.can_take(quests[3], ctx([], [1, 2])) == :ok
      assert QuestRequirements.can_take(quests[1], ctx([], [3])) == {:error, :breadcrumb_unavailable}
      assert QuestRequirements.can_take(quests[1], ctx([{3, :incomplete}])) == {:error, :breadcrumb_unavailable}
    end

    test "breadcrumb target conditions fail closed when missing and honor evaluated results" do
      quests = compile([%Quest{id: 1, breadcrumb_for_quest_id: 2}, %Quest{id: 2, required_condition_id: 42}])
      assert QuestRequirements.can_take(quests[1], ctx()) == {:error, :breadcrumb_unavailable}

      assert QuestRequirements.can_take(quests[1], Map.put(ctx(), :condition_results, %{2 => :unmet})) ==
               {:error, :breadcrumb_unavailable}

      assert QuestRequirements.can_take(quests[1], Map.put(ctx(), :condition_results, %{2 => :met})) == :ok
    end

    test "repeatable breadcrumbs still block after an earlier reward" do
      quests =
        compile([
          %Quest{id: 1, breadcrumb_for_quest_id: 2, special_flags: 1},
          %Quest{id: 2}
        ])

      for status <- [:incomplete, :complete, :failed] do
        assert QuestRequirements.can_take(quests[2], ctx([{1, status}], [1])) == {:error, :breadcrumb_active}
      end

      assert QuestRequirements.can_take(quests[2], ctx([], [1])) == :ok
    end

    test "invalid breadcrumb graphs cannot be accepted" do
      quests = compile([%Quest{id: 1, breadcrumb_for_quest_id: 1}])
      assert QuestRequirements.can_take(quests[1], ctx()) == {:error, :invalid_dependencies}
    end

    test "skill thresholds include both bonuses only for a known skill" do
      quest = %Quest{id: 1, required_skill: 185, required_skill_value: 50}
      assert QuestRequirements.can_take(quest, ctx()) == {:error, :low_skill}
      skilled = %{ctx() | skills: %{185 => %{value: 49}}}
      assert QuestRequirements.can_take(quest, skilled) == {:error, :low_skill}
      assert QuestRequirements.can_take(quest, %{skilled | skill_bonuses: %{185 => {2, -1}}}) == :ok
      assert QuestRequirements.can_take(quest, %{skilled | skills: %{185 => %{value: 50}}}) == :ok
      assert QuestRequirements.can_take(quest, %{ctx() | skill_bonuses: %{185 => {100, 100}}}) == {:error, :low_skill}
      assert QuestRequirements.can_take(%{quest | required_skill_value: 0}, ctx()) == :ok
    end
  end

  describe "for_npc/4" do
    test "unmet breadcrumb conditions suppress low-level markers" do
      quests =
        compile([
          %Quest{id: 1, min_level: 20, breadcrumb_for_quest_id: 2},
          %Quest{id: 2, required_condition_id: 42}
        ])

      context = %{ctx() | level: 1} |> Map.put(:condition_results, %{2 => :unmet})
      assert QuestDialogStatus.for_npc([quests[1]], [], context) == QuestDialogStatus.none()
    end

    test "missing dependencies and skills suppress low-level markers and menus" do
      quests = [
        %Quest{id: 1, prev_quest_id: 2, min_level: 60},
        %Quest{id: 3, required_skill: 185, required_skill_value: 50, min_level: 60}
      ]

      context = %{ctx() | level: 1}
      assert QuestDialogStatus.for_npc(quests, [], context) == QuestDialogStatus.none()
      assert QuestDialogStatus.menu(quests, [], context) == []

      assert QuestDialogStatus.for_npc([hd(quests)], [], %{context | rewarded_quests: MapSet.new([2])}) ==
               QuestDialogStatus.unavailable()
    end
  end
end
