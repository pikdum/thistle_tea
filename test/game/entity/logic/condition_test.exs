defmodule ThistleTea.Game.Entity.Logic.ConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionLogic

  setup [:mob]

  describe "met?/2" do
    test "nil condition is always met", %{mob: mob} do
      assert ConditionLogic.met?(mob, nil)
    end

    test "db_guid matches the spawn guid against any value", %{mob: mob} do
      assert ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 80_152})
      assert ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 1, value2: 80_152})
      refute ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 80_151, value2: 80_185})
    end

    test "db_guid fails without a spawn db guid", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | creature: %Creature{}}}
      refute ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 80_152})
    end

    test "source_entry matches the creature entry", %{mob: mob} do
      assert ConditionLogic.met?(mob, %Condition{type: :source_entry, value1: 38})
      assert ConditionLogic.met?(mob, %Condition{type: :source_entry, value1: 1, value3: 38})
      refute ConditionLogic.met?(mob, %Condition{type: :source_entry, value1: 39})
    end

    test "combinators evaluate their children", %{mob: mob} do
      match = %Condition{type: :db_guid, value1: 80_152}
      miss = %Condition{type: :db_guid, value1: 1}

      assert ConditionLogic.met?(mob, %Condition{type: :or, children: [miss, match]})
      refute ConditionLogic.met?(mob, %Condition{type: :or, children: [miss, miss]})
      assert ConditionLogic.met?(mob, %Condition{type: :and, children: [match, match]})
      refute ConditionLogic.met?(mob, %Condition{type: :and, children: [match, miss]})
      assert ConditionLogic.met?(mob, %Condition{type: :not, children: [miss]})
      refute ConditionLogic.met?(mob, %Condition{type: :not, children: [match]})
    end

    test "reverse flag negates the result", %{mob: mob} do
      refute ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 80_152, reverse?: true})
      assert ConditionLogic.met?(mob, %Condition{type: :db_guid, value1: 1, reverse?: true})
    end

    test "none and unsupported types are met", %{mob: mob} do
      assert ConditionLogic.met?(mob, %Condition{type: :none})
      assert ConditionLogic.met?(mob, %Condition{type: {:unsupported, 9}})
      assert ConditionLogic.met?(mob, %Condition{type: {:unsupported, :unresolved}})
    end
  end

  defp mob(_context) do
    mob = %{
      object: %Object{guid: 1, entry: 38},
      internal: %Internal{creature: %Creature{db_guid: 80_152}}
    }

    {:ok, mob: mob}
  end
end
