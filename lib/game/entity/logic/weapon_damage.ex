defmodule ThistleTea.Game.Entity.Logic.WeaponDamage do
  @moduledoc """
  Weapon-dependent damage inputs and aura multipliers shared by displayed
  ranged damage and attack snapshots.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Spell

  def wand?(%{subclass: 19}), do: true
  def wand?(_weapon), do: false

  def ranged_attack_power(%Unit{} = unit) do
    if wand?(unit.ranged_weapon), do: 0, else: unit.ranged_attack_power || 0
  end

  def prepare_spell(%{unit: %Unit{ranged_weapon: %{dmg_type1: school}}}, %Spell{} = spell) do
    if Spell.wand?(spell), do: %{spell | school: school}, else: spell
  end

  def prepare_spell(_caster, spell), do: spell

  def fits?(%{class: class, subclass: subclass, inventory_type: inventory_type}, %Spell{} = spell) do
    (spell.equipped_item_class in [-1, nil] or spell.equipped_item_class == class) and
      matches_mask?(spell.equipped_item_subclass_mask, subclass) and
      matches_mask?(spell.equipped_item_inventory_type_mask, inventory_type)
  end

  def fits?(_weapon, _spell), do: false

  def multiplier(%{unit: %Unit{auras: holders}}, school, weapon) when is_list(holders) do
    for %Holder{} = holder <- holders,
        applies?(holder.spell, weapon),
        %Aura{type: :mod_damage_percent_done, amount: amount, misc_value: mask} <- holder.auras,
        is_integer(amount) and is_integer(mask) and (mask &&& Spell.school_mask(school)) != 0,
        reduce: 1.0 do
      multiplier -> multiplier * max(100 + amount * max(holder.stacks || 1, 1), 0) / 100
    end
  end

  def multiplier(_entity, _school, _weapon), do: 1.0

  def flat_bonus(%{unit: %Unit{auras: holders}}, school, weapon) when is_list(holders) do
    for %Holder{} = holder <- holders,
        applies?(holder.spell, weapon),
        %Aura{type: :mod_damage_done, amount: amount, misc_value: mask} <- holder.auras,
        is_integer(amount) and is_integer(mask) and (mask &&& Spell.school_mask(school)) != 0,
        reduce: 0 do
      bonus -> bonus + amount * max(holder.stacks || 1, 1)
    end
  end

  def flat_bonus(_entity, _school, _weapon), do: 0

  defp applies?(%Spell{equipped_item_class: class}, _weapon) when class in [-1, nil], do: true
  defp applies?(%Spell{} = spell, weapon), do: fits?(weapon, spell)
  defp applies?(_spell, _weapon), do: true

  defp matches_mask?(mask, _value) when mask in [0, nil], do: true
  defp matches_mask?(mask, value) when is_integer(value) and value >= 0, do: (mask &&& 1 <<< value) != 0
  defp matches_mask?(_mask, _value), do: false
end
