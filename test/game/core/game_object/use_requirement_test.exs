defmodule ThistleTea.Game.Core.GameObject.UseRequirementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameObject.UseRequirement

  describe "from_row/2" do
    test "reads the dead-creature and active-object kinds and ignores others" do
      assert %UseRequirement{type: :dead_creature, db_guid: 52_161} = UseRequirement.from_row(0, 52_161)
      assert %UseRequirement{type: :active_object, db_guid: 17_904} = UseRequirement.from_row(1, 17_904)
      assert UseRequirement.from_row(2, 1) == nil
    end
  end

  describe "met?/2" do
    test "waits for a living creature to die and a closed object to open" do
      creature = UseRequirement.from_row(0, 1)
      coffer_door = UseRequirement.from_row(1, 2)

      refute UseRequirement.met?(creature, %{alive?: true})
      assert UseRequirement.met?(creature, %{alive?: false})
      refute UseRequirement.met?(coffer_door, %{go_state: 1})
      assert UseRequirement.met?(coffer_door, %{go_state: 0})
    end

    test "does not block on a spawn that is not loaded" do
      assert UseRequirement.met?(UseRequirement.from_row(0, 1), nil)
      assert UseRequirement.met?(UseRequirement.from_row(1, 2), nil)
    end
  end
end
