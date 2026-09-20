defmodule ThistleTea.Game.Entity.Logic.Enchantments do
  @moduledoc """
  Item-enchant target eligibility and recipe skill progression. Item and
  inventory facts are supplied by the owning player boundary.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell

  def permanent?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :enchant_item))

  def item_enchant?(%Spell{effects: effects}),
    do: Enum.any?(effects, &(&1.type in [:enchant_item, :enchant_item_temporary]))

  def target_guid(player, spell, target_guid) do
    if is_integer(target_guid) or permanent?(spell), do: target_guid, else: player.mainhand
  end

  def bound?(%Item{} = item, now, get_enchantment) do
    ((item.item.flags || 0) &&& 1) != 0 or
      Enum.any?(Item.active_enchantments(item, now), fn {_slot, id} ->
        case get_enchantment.(id) do
          %ItemEnchantment{flags: flags} when is_integer(flags) -> (flags &&& 1) != 0
          _ -> false
        end
      end)
  end

  def validate(character, %Spell{} = spell, item) do
    if item_enchant?(spell), do: validate_item(character, spell, item), else: :ok
  end

  def validate_item(%Character{} = character, %Spell{} = spell, %Item{} = item) do
    template = Item.template(item)

    cond do
      Core.dead?(character) -> {:error, :caster_dead}
      item.item.owner != character.object.guid -> {:error, :bad_targets}
      item.item.stack_count != 1 -> {:error, :bad_targets}
      not matches?(template, spell) -> {:error, :bad_targets}
      permanent?(spell) and template.item_level < spell.base_level -> {:error, :lowlevel}
      true -> :ok
    end
  end

  def validate_item(_character, _spell, _item), do: {:error, :item_gone}

  defp matches?(template, spell) do
    (spell.equipped_item_class < 0 or template.class == spell.equipped_item_class) and
      mask_matches?(spell.equipped_item_subclass_mask, template.subclass) and
      mask_matches?(spell.equipped_item_inventory_type_mask, template.inventory_type)
  end

  defp mask_matches?(mask, _value) when mask in [0, nil], do: true
  defp mask_matches?(mask, value) when is_integer(value), do: (mask &&& 1 <<< value) != 0
  defp mask_matches?(_mask, _value), do: false

  def skill_up(%Character{} = character, %{skill_id: id, yellow: yellow, gray: gray}, roll) do
    case Map.get(character.player.skills, id) do
      %{value: value, max: cap} = skill when value < cap ->
        if roll < gain_chance(value, yellow, gray) do
          skills = Map.put(character.player.skills, id, %{skill | value: value + 1})
          %{character | player: %{character.player | skills: skills}}
        else
          character
        end

      _ ->
        character
    end
  end

  def skill_up(character, _recipe, _roll), do: character

  defp gain_chance(value, _yellow, gray) when value >= gray, do: 0
  defp gain_chance(value, yellow, gray) when value >= div(yellow + gray, 2), do: 25
  defp gain_chance(value, yellow, _gray) when value >= yellow, do: 75
  defp gain_chance(_value, _yellow, _gray), do: 100
end
