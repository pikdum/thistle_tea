defmodule ThistleTea.Game.Core.Honor.ItemRequirementsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Honor.ItemRequirements

  describe "can_use?/2" do
    test "retains eligibility after losing current rank" do
      template = %ItemTemplate{required_honor_rank: 5}
      refute ItemRequirements.can_use?(%Player{}, template)
      refute ItemRequirements.can_use?(%Player{highest_honor_rank: 4}, template)
      assert ItemRequirements.can_use?(%Player{highest_honor_rank: 5, honor_rank: 0}, template)
      assert ItemRequirements.can_use?(%Player{highest_honor_rank: 18, honor_rank: 5}, template)
      assert ItemRequirements.can_use?(%Player{}, %ItemTemplate{})
    end
  end

  describe "can_buy?/2" do
    test "requires current rank and level only for ranked merchandise" do
      template = %ItemTemplate{required_honor_rank: 8, required_level: 30}
      character = %Character{player: %Player{honor_rank: 8, highest_honor_rank: 18}, unit: %Unit{level: 30}}
      assert ItemRequirements.can_buy?(character, template)
      refute ItemRequirements.can_buy?(%{character | player: %{character.player | honor_rank: 7}}, template)
      refute ItemRequirements.can_buy?(%{character | unit: %{character.unit | level: 29}}, template)
      assert ItemRequirements.can_buy?(character, %ItemTemplate{required_level: 60})
      refute ItemRequirements.can_buy?(%{character | player: %Player{}}, template)
    end
  end
end
