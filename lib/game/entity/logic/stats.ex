defmodule ThistleTea.Game.Entity.Logic.Stats do
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @resistance_fields [
    {0x01, :normal_resistance, :base_normal_resistance},
    {0x02, :holy_resistance, :base_holy_resistance},
    {0x04, :fire_resistance, :base_fire_resistance},
    {0x08, :nature_resistance, :base_nature_resistance},
    {0x10, :frost_resistance, :base_frost_resistance},
    {0x20, :shadow_resistance, :base_shadow_resistance},
    {0x40, :arcane_resistance, :base_arcane_resistance}
  ]

  @stat_fields [
    {0, :strength, :base_strength},
    {1, :agility, :base_agility},
    {2, :stamina, :base_stamina},
    {3, :intellect, :base_intellect},
    {4, :spirit, :base_spirit}
  ]

  @health_per_stamina 10
  @mana_per_intellect 15

  def sync_aura_mods(%Unit{} = unit) do
    unit
    |> reset_resistances()
    |> reset_stats()
    |> apply_resistance_mods()
    |> sync_derived_maxima()
  end

  defp reset_stats(%Unit{} = unit) do
    Enum.reduce(@stat_fields, unit, fn {_index, current_field, base_field}, acc ->
      base = base_value(acc, current_field, base_field)

      acc
      |> Map.put(base_field, base)
      |> Map.put(current_field, base)
    end)
  end

  defp sync_derived_maxima(%Unit{} = unit) do
    unit
    |> sync_derived_max(:stamina, :base_stamina, :max_health, :base_max_health, :health, @health_per_stamina)
    |> sync_derived_max(:intellect, :base_intellect, :max_power1, :base_max_power1, :power1, @mana_per_intellect)
  end

  defp sync_derived_max(
         %Unit{} = unit,
         stat_field,
         stat_base_field,
         max_field,
         max_base_field,
         current_field,
         per_point
       ) do
    with stat when is_integer(stat) <- Map.get(unit, stat_field),
         stat_base when is_integer(stat_base) <- Map.get(unit, stat_base_field),
         max_base when is_integer(max_base) and max_base > 0 <- base_value(unit, max_field, max_base_field) do
      new_max = max_base + (stat - stat_base) * per_point

      unit
      |> Map.put(max_base_field, max_base)
      |> Map.put(max_field, new_max)
      |> clamp_current(current_field, new_max)
    else
      _ -> unit
    end
  end

  defp clamp_current(%Unit{} = unit, current_field, new_max) do
    case Map.get(unit, current_field) do
      current when is_number(current) and current > new_max -> Map.put(unit, current_field, new_max)
      _ -> unit
    end
  end

  defp reset_resistances(%Unit{} = unit) do
    Enum.reduce(@resistance_fields, unit, fn {_mask, current_field, base_field}, acc ->
      base = base_value(acc, current_field, base_field)

      acc
      |> Map.put(base_field, base)
      |> Map.put(current_field, base)
    end)
  end

  defp base_value(%Unit{} = unit, current_field, base_field) do
    cond do
      is_integer(Map.get(unit, base_field)) -> Map.get(unit, base_field)
      is_integer(Map.get(unit, current_field)) -> Map.get(unit, current_field)
      true -> 0
    end
  end

  defp apply_resistance_mods(%Unit{auras: holders} = unit) when is_list(holders) do
    Enum.reduce(holders, unit, fn %Holder{auras: auras}, acc ->
      Enum.reduce(auras, acc, &apply_aura_mod/2)
    end)
  end

  defp apply_resistance_mods(unit), do: unit

  defp apply_aura_mod(%Aura{type: :mod_resistance, amount: amount, misc_value: mask}, %Unit{} = unit)
       when is_integer(amount) do
    Enum.reduce(resistance_fields_for_mask(mask), unit, fn field, acc ->
      Map.update!(acc, field, &(&1 + amount))
    end)
  end

  defp apply_aura_mod(%Aura{type: :mod_stat, amount: amount, misc_value: misc}, %Unit{} = unit)
       when is_integer(amount) do
    Enum.reduce(stat_fields_for_misc(misc), unit, fn field, acc ->
      Map.update!(acc, field, &((&1 || 0) + amount))
    end)
  end

  defp apply_aura_mod(_aura, unit), do: unit

  defp stat_fields_for_misc(-1), do: Enum.map(@stat_fields, fn {_index, field, _base} -> field end)

  defp stat_fields_for_misc(misc) when is_integer(misc) do
    @stat_fields
    |> Enum.filter(fn {index, _field, _base} -> index == misc end)
    |> Enum.map(fn {_index, field, _base} -> field end)
  end

  defp stat_fields_for_misc(_misc), do: []

  defp resistance_fields_for_mask(mask) when is_integer(mask) do
    @resistance_fields
    |> Enum.filter(fn {bit, _current_field, _base_field} -> (mask &&& bit) != 0 end)
    |> Enum.map(fn {_bit, current_field, _base_field} -> current_field end)
  end

  defp resistance_fields_for_mask(_mask), do: []
end
