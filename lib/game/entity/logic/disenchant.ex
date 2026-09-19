defmodule ThistleTea.Game.Entity.Logic.Disenchant do
  @moduledoc """
  Disenchant eligibility and vanilla Enchanting progression. Any trained
  enchanter can disenchant eligible owned equipment regardless of item level.
  Skill gains become yellow at 20, green at 40, and gray at 60.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell

  @skill 333
  @no_disenchant 0x8000

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :disenchant))

  def validate(caster, %Spell{} = spell, item) do
    if spell?(spell), do: validate_item(caster, item), else: :ok
  end

  def validate_item(%Character{} = character, %Item{} = item) do
    cond do
      Core.dead?(character) -> {:error, :caster_dead}
      not is_nil(character.internal.item_loot) -> {:error, :already_open}
      Skills.value(character.player.skills, @skill) < 1 -> {:error, :low_castlevel}
      item.item.owner != character.object.guid -> {:error, :cant_be_disenchanted}
      item.item.stack_count != 1 -> {:error, :cant_be_disenchanted}
      not eligible?(Item.template(item)) -> {:error, :cant_be_disenchanted}
      true -> :ok
    end
  end

  def validate_item(_character, _item), do: {:error, :cant_be_disenchanted}

  defp eligible?(%ItemTemplate{disenchant_id: id, flags: flags}) do
    is_integer(id) and id > 0 and ((flags || 0) &&& @no_disenchant) == 0
  end

  defp eligible?(_template), do: false

  def skill_up(%Character{} = character, roll) when is_number(roll) do
    case Map.get(character.player.skills, @skill) do
      %{value: value, max: cap} = skill when value < cap ->
        if roll < gain_chance(value) do
          skills = Map.put(character.player.skills, @skill, %{skill | value: value + 1})
          %{character | player: %{character.player | skills: skills}}
        else
          character
        end

      _ ->
        character
    end
  end

  def gain_chance(value) when value >= 60, do: 0
  def gain_chance(value) when value >= 40, do: 25
  def gain_chance(value) when value >= 20, do: 75
  def gain_chance(_value), do: 100
end
