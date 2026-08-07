defmodule ThistleTea.Game.Entity.Data.ConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Condition

  describe "type/1" do
    test "maps every condition ID in the pinned VMangos enum" do
      assert Condition.known_types() |> Map.keys() |> Enum.sort() == Enum.to_list(-3..59)

      Enum.each(-3..59, fn id ->
        refute match?({:unsupported, _id}, Condition.type(id))
      end)
    end

    test "preserves genuinely unknown upstream IDs" do
      assert Condition.type(60) == {:unsupported, 60}
    end
  end

  describe "build/2" do
    test "retains raw values and flags" do
      row = %{condition_entry: 7, type: 15, value1: 20, value2: 1, value3: 2, value4: 3, flags: 3}

      assert %Condition{
               entry: 7,
               type: :level,
               value1: 20,
               value2: 1,
               value3: 2,
               value4: 3,
               reverse?: true,
               swap_targets?: true
             } = Condition.build(row, [])
    end

    test "marks malformed referenced trees unresolved" do
      row = %{condition_entry: 7, type: -1, value1: 1, value2: 2, value3: 0, value4: 0, flags: 0}

      assert %Condition{type: {:unsupported, :unresolved}} = Condition.build(row, [Condition.unresolved(1)])
    end
  end
end
