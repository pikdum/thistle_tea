defmodule ThistleTea.Game.Entity.Logic.AttackPower do
  @moduledoc """
  Flat and percentage attack-power modifiers, with the creature damage model
  anchored to the unmodified seed rather than the current damage snapshot.
  Hunter pets retain their level's strength baseline; summoned pets and imps
  compare flat AP modifiers against their current strength-derived baseline.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic

  def total(%Unit{} = unit, base, kind) when is_number(base) and kind in [:melee, :ranged] do
    {flat_type, percent_type, equipment_key} = modifier_types(kind)
    flat = AuraLogic.flat_amount(%{unit: unit}, flat_type)
    equipment = Map.get(unit.equipment_bonuses || %{}, equipment_key, 0)
    max(trunc((base + flat + equipment) * multiplier(unit.auras, percent_type)), 0)
  end

  def creature_multiplier(%Unit{} = unit, :melee) do
    base =
      if unit.attack_power_model in [:summoned_pet, :imp],
        do: pet_base(unit),
        else: unit.base_attack_power

    ratio(base, unit.attack_power)
  end

  def creature_multiplier(%Unit{base_ranged_attack_power: base, ranged_attack_power: current}, :ranged),
    do: ratio(base, current)

  defp ratio(base, current) when is_number(base) and base > 0 and is_number(current),
    do: (7 * base + 3 * max(current, 0)) / (10 * base)

  defp ratio(_base, _current), do: 1.0

  def pet_base(%Unit{attack_power_model: :imp, strength: strength}), do: strength - 10
  def pet_base(%Unit{strength: strength}), do: strength * 2 - 20

  def creature?(%Unit{base_attack_power: base}), do: is_number(base)

  def weapon_range(%Unit{} = unit, :melee) do
    {weapon_value(unit, unit.base_min_damage, unit.min_damage, :melee),
     weapon_value(unit, unit.base_max_damage, unit.max_damage, :melee)}
  end

  def weapon_range(%Unit{} = unit, :ranged) do
    {weapon_value(unit, unit.base_ranged_min_damage, unit.min_ranged_damage, :ranged),
     weapon_value(unit, unit.base_ranged_max_damage, unit.max_ranged_damage, :ranged)}
  end

  defp weapon_value(unit, base, _current, kind) when is_number(base),
    do: if(creature?(unit), do: base * creature_multiplier(unit, kind), else: base)

  defp weapon_value(_unit, _base, current, _kind), do: current || 0

  defp modifier_types(:melee), do: {:mod_attack_power, :mod_attack_power_pct, :attack_power}
  defp modifier_types(:ranged), do: {:mod_ranged_attack_power, :mod_ranged_attack_power_pct, :ranged_attack_power}

  defp multiplier(holders, type) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %Aura{type: ^type, amount: amount} <- auras,
        is_number(amount),
        reduce: 1.0 do
      value -> value * max(100 + amount * max(stacks || 1, 1), 0) / 100
    end
  end

  defp multiplier(_holders, _type), do: 1.0
end
