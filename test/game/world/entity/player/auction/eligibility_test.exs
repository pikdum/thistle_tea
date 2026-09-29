defmodule ThistleTea.Game.World.Entity.Player.Auction.EligibilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.World.Entity.Player.Auction.Eligibility

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
