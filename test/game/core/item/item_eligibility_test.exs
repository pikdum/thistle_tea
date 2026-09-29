defmodule ThistleTea.Game.Core.Item.ItemEligibilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.ItemEligibility
  alias ThistleTea.Game.Core.Item.Proficiency

  describe "check/2" do
    setup [:character]

    test "shares all item-use requirements with inventory", %{character: character} do
      snapshot = ItemEligibility.from_character(character)
      proficiency = Proficiency.from_character(character)

      for {template, expected} <- [
            {%ItemTemplate{}, :ok},
            {%ItemTemplate{allowable_class: 2}, {:error, :you_can_never_use_that_item}},
            {%ItemTemplate{allowable_race: 2}, {:error, :you_can_never_use_that_item}},
            {%ItemTemplate{required_level: 21}, {:error, :cant_equip_level_i}},
            {%ItemTemplate{required_honor_rank: 6}, :ok},
            {%ItemTemplate{required_honor_rank: 7}, {:error, :cant_equip_rank}},
            {%ItemTemplate{required_skill: 164, required_skill_rank: 100}, :ok},
            {%ItemTemplate{required_skill: 164, required_skill_rank: 101}, {:error, :no_required_proficiency}},
            {%ItemTemplate{required_skill: 165}, {:error, :no_required_proficiency}},
            {%ItemTemplate{required_spell: 9788}, :ok},
            {%ItemTemplate{required_spell: 9787}, {:error, :no_required_proficiency}},
            {%ItemTemplate{class: 2, subclass: 8}, {:error, :no_required_proficiency}},
            {%ItemTemplate{class: 4, subclass: 4}, {:error, :no_required_proficiency}}
          ] do
        assert ItemEligibility.check(snapshot, template) == expected
        assert Inventory.can_use(character.unit, proficiency, template, character.player) == expected
      end
    end

    test "requires a complete character snapshot and an item template", %{character: character} do
      assert ItemEligibility.from_character(%Character{}) == nil
      assert ItemEligibility.check(nil, %ItemTemplate{}) == {:error, :item_not_found}
      assert ItemEligibility.check(ItemEligibility.from_character(character), nil) == {:error, :item_not_found}
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        unit: %Unit{class: 1, race: 1, level: 20},
        player: %Player{honor_rank: 1, highest_honor_rank: 6, skills: %{164 => %{value: 100}}},
        internal: %Internal{spells: [9788]}
      }
    }
  end
end
