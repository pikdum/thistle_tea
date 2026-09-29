defmodule ThistleTea.Game.World.Entity.Player.Auction.Eligibility do
  @moduledoc """
  Resolves the auction search's usable-items filter from equipment rules,
  reputation, required spells, and already learned recipes.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def usable?(%Character{} = character, %Item{} = item, get_spell \\ &SpellLoader.load/1) do
    template = Item.template(item)
    known = character.internal.spells || []

    Inventory.can_use(character.unit, Proficiency.from_character(character), template, character.player) == :ok and
      Reputation.validate_item_requirement(character, template) == :ok and
      not known_recipe?(template, known, get_spell)
  end

  defp known_recipe?(%ItemTemplate{class: 9, spellid_1: spell_id}, known, get_spell) when spell_id > 0 do
    case get_spell.(spell_id) do
      %Spell{effects: effects} -> Enum.any?(effects, &(&1.type == :learn_spell and &1.trigger_spell_id in known))
      _ -> false
    end
  end

  defp known_recipe?(_template, _known, _get_spell), do: false
end
