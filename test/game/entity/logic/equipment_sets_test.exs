defmodule ThistleTea.Game.Entity.Logic.EquipmentSetsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemSet
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.EquipmentSets
  alias ThistleTea.Game.Entity.Logic.Inventory

  setup [:equipment]

  describe "sources/3" do
    test "grants cumulative thresholds once per set", %{character: character, templates: templates, get_set: get_set} do
      assert EquipmentSets.sources(character, Enum.take(templates, 1), get_set) == []
      assert EquipmentSets.sources(character, Enum.take(templates, 2), get_set) == [{:item_set, 1, 101}]
      assert EquipmentSets.sources(character, templates, get_set) == [{:item_set, 1, 101}, {:item_set, 1, 102}]
    end

    test "keeps separate sets with the same spell independent", %{character: character, get_set: get_set} do
      templates = for id <- [1, 1, 2, 2, 0, 999], do: %ItemTemplate{item_set: id}
      assert EquipmentSets.sources(character, templates, get_set) == [{:item_set, 1, 101}, {:item_set, 2, 101}]
    end

    test "requires the profession and its rank", %{character: character, templates: templates} do
      set = %ItemSet{id: 1, required_skill: 197, required_skill_rank: 300, bonuses: [{3, 101}]}
      get_set = fn 1 -> set end
      assert EquipmentSets.sources(character, templates, get_set) == []
      character = put_in(character.player.skills, %{197 => %{value: 299, max: 300}})
      assert EquipmentSets.sources(character, templates, get_set) == []
      character = put_in(character.player.skills[197].value, 300)
      assert EquipmentSets.sources(character, templates, get_set) == [{:item_set, 1, 101}]
    end

    test "counts broken equipped items and excludes backpack and bank contents", %{
      character: character,
      get_set: get_set
    } do
      template = %ItemTemplate{entry: 1, item_set: 1, max_durability: 100}
      item = Item.build(template, 10)
      broken = %{item | item: %{item.item | durability: 0}}
      player = %{character.player | head: 10, chest: 11, inv1: 12, bank1: 13}
      templates = Inventory.equipped_templates(player, fn _guid -> broken end)
      assert length(templates) == 2
      assert EquipmentSets.sources(character, templates, get_set) == [{:item_set, 1, 101}]
    end
  end

  defp equipment(_context) do
    sets = %{
      1 => %ItemSet{id: 1, bonuses: [{2, 101}, {3, 102}, {3, 101}]},
      2 => %ItemSet{id: 2, bonuses: [{2, 101}]}
    }

    %{
      character: %Character{player: %Player{}, unit: %Unit{auras: []}},
      templates: for(id <- 1..3, do: %ItemTemplate{entry: id, item_set: 1}),
      get_set: &Map.get(sets, &1)
    }
  end
end
