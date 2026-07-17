defmodule ThistleTea.Game.Entity.Logic.AI.BT.RangedTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Ranged

  describe "active?/2" do
    test "tracks and stops an active auto shot" do
      character = %Character{internal: %Internal{auto_shot: %{target_guid: 7}}}

      assert Ranged.active?(character, Blackboard.new())
      refute character |> Ranged.stop() |> Ranged.active?(Blackboard.new())
    end
  end
end
