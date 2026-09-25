defmodule ThistleTea.Game.Entity.Logic.AttackSpeed do
  @moduledoc "Derives weapon periods from equipment, form, and independent haste or slow effects."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackPower
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Spell

  @fields [mainhand: :base_attack_time, offhand: :offhand_attack_time, ranged: :ranged_attack_time]

  def recompute(%Unit{} = unit) do
    Enum.reduce(@fields, unit, fn {hand, field}, current ->
      case base_period(unit, hand) do
        base when is_number(base) and base > 0 ->
          struct!(current, [{field, max(trunc(base * multiplier(unit, hand)), 1)}])

        _missing ->
          current
      end
    end)
  end

  def base_ms(%Unit{} = unit, hand), do: base_period(unit, hand) || 2_000

  defp base_period(%Unit{class: 11, shapeshift_form: 1}, :mainhand), do: 1_000
  defp base_period(%Unit{class: 11, shapeshift_form: form}, :mainhand) when form in [5, 8], do: 2_500

  defp base_period(%Unit{base_melee_attack_time: base} = unit, :mainhand) when is_number(base) and base > 0 do
    if not AttackPower.creature?(unit) and Disarm.unarmed?(unit), do: 2_000, else: base
  end

  defp base_period(%Unit{}, :mainhand), do: nil
  defp base_period(%Unit{base_offhand_attack_time: base}, :offhand), do: base
  defp base_period(%Unit{base_ranged_attack_time: base}, :ranged), do: base

  def multiplier(%Unit{auras: holders} = unit, hand) do
    {amounts, slow} =
      for %Holder{} = holder <- holders || [],
          %Aura{type: type, amount: amount} <- holder.auras,
          applies?(type, hand, unit) and is_number(amount),
          reduce: {[], 0} do
        {amounts, slow} ->
          amount = amount * max(holder.stacks || 1, 1)

          if exclusive_slow?(holder, type, amount) do
            {amounts, min(slow, amount)}
          else
            {[amount | amounts], slow}
          end
      end

    Enum.reduce([slow | amounts], equipment_multiplier(unit, hand), &(&2 * factor(&1)))
  end

  defp applies?(:mod_attack_speed, _hand, _unit), do: true
  defp applies?(:mod_melee_haste, hand, _unit), do: hand in [:mainhand, :offhand]
  defp applies?(:mod_ranged_haste, :ranged, _unit), do: true
  defp applies?(:mod_ranged_ammo_haste, :ranged, unit), do: ammunition_weapon?(unit)
  defp applies?(_type, _hand, _unit), do: false

  defp exclusive_slow?(%Holder{spell: %Spell{} = spell}, :mod_melee_haste, amount),
    do: amount < 0 and not Spell.attribute?(spell, :passive)

  defp exclusive_slow?(_holder, _type, _amount), do: false

  defp equipment_multiplier(%Unit{equipment_bonuses: bonuses} = unit, :ranged) when is_map(bonuses) do
    ammo_haste = if ammunition_weapon?(unit), do: Map.get(bonuses, :ranged_ammo_haste, 0), else: 0
    factor(Map.get(bonuses, :ranged_haste, 0)) * factor(ammo_haste)
  end

  defp equipment_multiplier(_unit, _hand), do: 1.0

  defp ammunition_weapon?(%Unit{ranged_weapon: %{ammo_type: type}} = unit) when is_integer(type) and type > 0,
    do: not AttackPower.creature?(unit)

  defp ammunition_weapon?(_unit), do: false

  defp factor(amount) when amount >= 0, do: 100 / (100 + amount)
  defp factor(amount), do: (100 - amount) / 100
end
