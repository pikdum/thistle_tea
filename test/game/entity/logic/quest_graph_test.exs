defmodule ThistleTea.Game.Entity.Logic.QuestGraphTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.QuestDependencies.Prerequisite
  alias ThistleTea.Game.Entity.Logic.QuestGraph

  describe "compile/1" do
    test "merges signed incoming prerequisites deterministically without duplicate edges" do
      quests = [
        %Quest{id: 1, next_quest_id: 4},
        %Quest{id: 2, next_quest_id: -4},
        %Quest{id: 3, next_quest_id: 4},
        %Quest{id: 4, prev_quest_id: 1}
      ]

      assert QuestGraph.compile(quests) == QuestGraph.compile(Enum.reverse(quests))
      quest = quests |> QuestGraph.compile() |> List.last()

      assert quest.dependencies.prerequisites == [
               %Prerequisite{quest_id: 1, state: :rewarded, group_quests: [1]},
               %Prerequisite{quest_id: 2, state: :current, group_quests: [2]},
               %Prerequisite{quest_id: 3, state: :rewarded, group_quests: [3]}
             ]
    end

    test "resolves exclusive alternatives and all-of prerequisite groups independently" do
      [first, second, _, _, followup] =
        QuestGraph.compile([
          %Quest{id: 1, exclusive_group: 10},
          %Quest{id: 2, exclusive_group: 10, special_flags: 1},
          %Quest{id: 3, exclusive_group: -10},
          %Quest{id: 4, exclusive_group: -10},
          %Quest{id: 5, prev_quest_id: -3}
        ])

      assert first.dependencies.exclusive_quests == [{2, true}]
      assert second.dependencies.exclusive_quests == [{1, false}]

      assert followup.dependencies.prerequisites == [
               %Prerequisite{quest_id: 3, state: :current, group_quests: [3, 4]}
             ]
    end

    test "indexes immediate chain predecessors without inventing prerequisites" do
      [first, middle, last] =
        QuestGraph.compile([
          %Quest{id: 1, next_quest_in_chain: 2},
          %Quest{id: 2, next_quest_in_chain: 3, special_flags: 1},
          %Quest{id: 3}
        ])

      assert first.dependencies.next_chain_quest == {2, true}
      assert middle.dependencies.previous_chain_quests == [1]
      assert last.dependencies.previous_chain_quests == [2]
      assert middle.dependencies.prerequisites == []
    end

    test "flattens breadcrumb targets and indexes transitive dependents" do
      [first, middle, last] =
        QuestGraph.compile([
          %Quest{id: 1, breadcrumb_for_quest_id: 2, special_flags: 1},
          %Quest{id: 2, breadcrumb_for_quest_id: 3, prev_quest_id: 1},
          %Quest{id: 3, prev_quest_id: 2}
        ])

      assert Enum.map(first.dependencies.breadcrumb_targets, & &1.id) == [2, 3]
      assert Enum.all?(first.dependencies.breadcrumb_targets, &(&1.dependencies.breadcrumb_targets == []))
      assert middle.dependencies.dependent_breadcrumb_quests == [{1, true}]
      assert last.dependencies.dependent_breadcrumb_quests == [{1, true}, {2, false}]
      assert middle.dependencies.prerequisites == []
      assert last.dependencies.prerequisites == []
    end

    test "invalid breadcrumb paths fail closed and ordinary missing links are ignored" do
      quests =
        QuestGraph.compile([
          %Quest{id: 1, breadcrumb_for_quest_id: 2},
          %Quest{id: 2, breadcrumb_for_quest_id: 1},
          %Quest{id: 3, breadcrumb_for_quest_id: 4},
          %Quest{id: 5, breadcrumb_for_quest_id: 3},
          %Quest{id: 6, prev_quest_id: 99, next_quest_in_chain: 100}
        ])

      assert Enum.all?(Enum.take(quests, 4), &(not &1.dependencies.valid?))
      assert Enum.all?(Enum.take(quests, 4), &(&1.dependencies.breadcrumb_targets == []))
      assert List.last(quests).dependencies.valid?
      assert List.last(quests).dependencies.prerequisites == []
      assert List.last(quests).dependencies.next_chain_quest == nil
    end
  end
end
