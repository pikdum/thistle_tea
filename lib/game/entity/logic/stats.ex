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

  def sync_aura_mods(%Unit{} = unit) do
    unit
    |> reset_resistances()
    |> apply_resistance_mods()
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

  defp apply_aura_mod(_aura, unit), do: unit

  defp resistance_fields_for_mask(mask) when is_integer(mask) do
    @resistance_fields
    |> Enum.filter(fn {bit, _current_field, _base_field} -> (mask &&& bit) != 0 end)
    |> Enum.map(fn {_bit, current_field, _base_field} -> current_field end)
  end

  defp resistance_fields_for_mask(_mask), do: []
end
