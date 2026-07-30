defmodule ThistleTea.Game.Player.GossipConditionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Player.GossipCondition

  describe "met?/2" do
    test "gates a Moonglade taxi option by faction and druid class" do
      alliance = %Character{unit: %Unit{race: 1, class: 11}}
      horde = %Character{unit: %Unit{race: 2, class: 11}}
      warrior = %Character{unit: %Unit{race: 1, class: 1}}

      condition = %Condition{
        type: :and,
        children: [
          %Condition{type: {:unsupported, 6}, value1: 469},
          %Condition{type: {:unsupported, 14}, value1: 0, value2: 1024}
        ]
      }

      assert GossipCondition.met?(alliance, condition)
      refute GossipCondition.met?(horde, condition)
      refute GossipCondition.met?(warrior, condition)
    end
  end
end
