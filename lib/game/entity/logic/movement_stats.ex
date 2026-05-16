defmodule ThistleTea.Game.Entity.Logic.MovementStats do
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @speed_fields [
    {:walk_speed, :base_walk_speed},
    {:run_speed, :base_run_speed},
    {:run_back_speed, :base_run_back_speed},
    {:swim_speed, :base_swim_speed},
    {:swim_back_speed, :base_swim_back_speed}
  ]

  def sync_aura_mods(%{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = entity) do
    modifier = speed_modifier(unit)
    movement_block = apply_speed_modifier(movement_block, modifier)
    %{entity | movement_block: movement_block}
  end

  def sync_aura_mods(entity), do: entity

  defp speed_modifier(%Unit{auras: holders}) when is_list(holders) do
    holders
    |> Enum.flat_map(fn
      %Holder{auras: auras} -> auras
      _ -> []
    end)
    |> Enum.reduce(0, fn
      %Aura{type: :mod_decrease_speed, amount: amount}, acc when is_integer(amount) -> acc + amount
      %Aura{type: :mod_increase_speed, amount: amount}, acc when is_integer(amount) -> acc + amount
      _aura, acc -> acc
    end)
  end

  defp speed_modifier(_unit), do: 0

  defp apply_speed_modifier(%MovementBlock{} = movement_block, modifier) do
    multiplier = max((100 + modifier) / 100, 0.0)

    Enum.reduce(@speed_fields, movement_block, fn {current_field, base_field}, acc ->
      base = base_value(acc, current_field, base_field)

      acc
      |> Map.put(base_field, base)
      |> Map.put(current_field, base * multiplier)
    end)
  end

  defp base_value(%MovementBlock{} = movement_block, current_field, base_field) do
    cond do
      is_number(Map.get(movement_block, base_field)) -> Map.get(movement_block, base_field)
      is_number(Map.get(movement_block, current_field)) -> Map.get(movement_block, current_field)
      true -> 0.0
    end
  end
end
