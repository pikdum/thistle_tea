defmodule ThistleTea.Game.World.Loader.QuestTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  describe "attach_required_condition/2" do
    test "attaches a supplied resolved tree" do
      tree = %Condition{entry: 42, type: :quest_rewarded, value1: 7}
      quest = %Quest{id: 1, required_condition_id: 42}

      assert %Quest{required_condition: ^tree} = QuestLoader.attach_required_condition(quest, %{42 => tree})
    end

    test "preserves a missing nonzero root as unresolved" do
      quest = %Quest{id: 1, required_condition_id: 42}

      assert %Quest{required_condition: %Condition{entry: 42, type: {:unsupported, :unresolved}}} =
               QuestLoader.attach_required_condition(quest, %{})
    end

    test "leaves an unconditioned quest without a tree" do
      quest = %Quest{id: 1}

      assert %Quest{required_condition: nil} = QuestLoader.attach_required_condition(quest, %{})
    end
  end
end
