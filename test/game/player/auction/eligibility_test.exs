defmodule ThistleTea.Game.Player.Auction.EligibilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Player.Auction.Eligibility
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "usable?/3" do
    test "checks level, class, proficiency, and required spells" do
      character = character()
      assert usable?(character, %ItemTemplate{entry: 1})
      refute usable?(character, %ItemTemplate{entry: 1, required_level: 61})
      refute usable?(character, %ItemTemplate{entry: 1, allowable_class: 128})
      refute usable?(character, %ItemTemplate{entry: 1, class: 2, subclass: 0})
      refute usable?(character, %ItemTemplate{entry: 1, required_spell: 200})
      assert usable?(character, %ItemTemplate{entry: 1, required_spell: 100})
    end

    test "excludes learned recipes while leaving unknown recipes visible" do
      recipe = Item.build(%ItemTemplate{entry: 1, class: 9, spellid_1: 500}, 10)
      spell = %Spell{id: 500, effects: [%Effect{index: 0, type: :learn_spell, trigger_spell_id: 100}]}
      refute Eligibility.usable?(character(), recipe, fn 500 -> spell end)
      unknown = %{character() | internal: %Internal{spells: [], spellbook: %{}}}
      assert Eligibility.usable?(unknown, recipe, fn 500 -> spell end)
    end
  end

  defp usable?(character, template), do: Eligibility.usable?(character, Item.build(template, 10), fn _ -> nil end)

  defp character do
    %Character{
      unit: %Unit{level: 60, race: 1, class: 1},
      player: %Player{},
      internal: %Internal{spells: [100], spellbook: %{}}
    }
  end
end
