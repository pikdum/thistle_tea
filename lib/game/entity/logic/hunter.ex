defmodule ThistleTea.Game.Entity.Logic.Hunter do
  @moduledoc """
  Pure Hunter ranged-ammunition rules derived from the equipped weapon and
  selected projectile item.
  """
  alias ThistleTea.Game.Spell

  @item_class_projectile 6

  def validate_ammo(%Spell{} = spell, ammo_id, ammo_template, equipped_items, count_item)
      when is_list(equipped_items) do
    if Spell.ranged_ability?(spell) do
      validate_projectile(ammo_id, ammo_template, ranged_weapon(equipped_items), count_item)
    else
      :ok
    end
  end

  def ammo_reagents(%{player: %{ammo_id: ammo_id}}, %Spell{} = spell) when is_integer(ammo_id) and ammo_id > 0 do
    if Spell.ranged_ability?(spell), do: [{ammo_id, 1}], else: []
  end

  def ammo_reagents(_character, _spell), do: []

  def validate_tame(%{unit: %{summon: summon}}, %Spell{name: "Tame Beast"}, _target)
      when is_integer(summon) and summon > 0, do: {:error, :already_have_summon}

  def validate_tame(%{unit: %{level: level}}, %Spell{name: "Tame Beast"}, %{tameable?: true, level: target_level})
      when is_integer(level) and is_integer(target_level) and target_level <= level, do: :ok

  def validate_tame(_caster, %Spell{name: "Tame Beast"}, _target), do: {:error, :bad_targets}
  def validate_tame(_caster, _spell, _target), do: :ok

  defp validate_projectile(_ammo_id, _ammo, %{ammo_type: 0}, _count_item), do: :ok

  defp validate_projectile(
         ammo_id,
         %{class: @item_class_projectile, subclass: subclass},
         %{ammo_type: subclass},
         count_item
       )
       when is_integer(ammo_id) and ammo_id > 0 and is_function(count_item, 1) do
    if count_item.(ammo_id) > 0, do: :ok, else: {:error, :no_ammo}
  end

  defp validate_projectile(_ammo_id, _ammo, _weapon, _count_item), do: {:error, :no_ammo}

  defp ranged_weapon(items),
    do: Enum.find(items, &match?(%{class: 2, inventory_type: type} when type in [15, 25, 26], &1))
end
