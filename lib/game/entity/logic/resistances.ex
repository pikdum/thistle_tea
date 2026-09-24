defmodule ThistleTea.Game.Entity.Logic.Resistances do
  @moduledoc """
  Derives armor and school resistances from base values, equipment, stats, and
  auras. Base modifiers precede stat and flat aura bonuses; independent
  percentage effects multiply within each layer.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @schools [
    {0x01, :normal_resistance, :base_normal_resistance, :armor},
    {0x02, :holy_resistance, :base_holy_resistance, :holy},
    {0x04, :fire_resistance, :base_fire_resistance, :fire},
    {0x08, :nature_resistance, :base_nature_resistance, :nature},
    {0x10, :frost_resistance, :base_frost_resistance, :frost},
    {0x20, :shadow_resistance, :base_shadow_resistance, :shadow},
    {0x40, :arcane_resistance, :base_arcane_resistance, :arcane}
  ]

  def recompute(%Unit{} = unit) do
    Enum.reduce(@schools, unit, fn {bit, field, base_field, equipment_key}, acc ->
      base = Map.fetch!(unit, base_field) || 0
      equipment = Map.get(unit.equipment_bonuses || %{}, equipment_key, 0)
      initial = base + equipment + flat(unit, bit, :mod_base_resistance)
      scaled = initial * multiplier(unit, bit, :mod_base_resistance_percent)
      total = scaled + stat_bonus(unit, bit) + flat(unit, bit, :mod_resistance) + exclusive(unit, bit)
      value = trunc(total * multiplier(unit, bit, :mod_resistance_percent))
      struct!(acc, [{field, if(base < 0, do: value, else: max(value, 0))}])
    end)
  end

  defp stat_bonus(%Unit{} = unit, bit) do
    intellect_bonus = (unit.intellect || 0) * flat(unit, bit, :mod_resistance_of_stat_percent) / 100
    agility_armor(unit, bit) + intellect_bonus
  end

  defp agility_armor(%Unit{attack_power_model: :hunter_pet, agility: agility}, 0x01), do: (agility || 0) * 2
  defp agility_armor(%Unit{stat_model: :creature, agility: agility}, 0x01), do: agility || 0
  defp agility_armor(%Unit{agility: agility}, 0x01), do: (agility || 0) * 2
  defp agility_armor(_unit, _bit), do: 0

  defp flat(unit, bit, type), do: unit |> amounts(bit, type) |> Enum.sum()

  defp exclusive(unit, bit) do
    values = [0 | amounts(unit, bit, :mod_resistance_exclusive)]
    Enum.max(values) + Enum.min(values)
  end

  defp multiplier(unit, bit, type) do
    unit
    |> amounts(bit, type)
    |> Enum.reduce(1.0, fn amount, product -> product * max(100 + amount, 0) / 100 end)
  end

  defp amounts(%Unit{auras: holders}, bit, type) do
    for %Holder{auras: auras, stacks: stacks} <- holders || [],
        %Aura{type: ^type, amount: amount, misc_value: mask} <- auras,
        is_number(amount) and is_integer(mask) and (mask &&& bit) != 0,
        do: amount * max(stacks || 1, 1)
  end
end
