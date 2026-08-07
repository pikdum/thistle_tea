defmodule ThistleTea.Game.Entity.Logic.Condition.RequirementsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements

  describe "plan/1" do
    test "aggregates and deduplicates leaf requirements" do
      conditions = [
        %Condition{type: :active_game_event, value1: 12},
        %Condition{type: :active_game_event, value1: 12},
        %Condition{type: :nearby_game_object, value1: 21_145, value2: 30}
      ]

      assert Requirements.plan(conditions) ==
               MapSet.new([
                 {:active_game_event, 12},
                 {:nearby_game_object, :target, 21_145, 30}
               ])
    end

    test "propagates swapped selectors through nested trees" do
      condition = %Condition{
        type: :and,
        swap_targets?: true,
        children: [
          %Condition{type: :source_entry},
          %Condition{type: :line_of_sight},
          %Condition{type: :source_entry, swap_targets?: true}
        ]
      }

      assert Requirements.plan(condition) ==
               MapSet.new([
                 {:subject, :target, :entry},
                 {:line_of_sight, :target, :source},
                 {:subject, :source, :entry}
               ])
    end
  end

  describe "environment_conditions/1" do
    test "keeps distinct unresolved-entry requirements" do
      conditions = [
        %Condition{type: :nearby_creature, value1: 1, value2: 10},
        %Condition{type: :nearby_creature, value1: 2, value2: 20}
      ]

      assert Requirements.environment_conditions(conditions) == conditions
    end
  end
end
