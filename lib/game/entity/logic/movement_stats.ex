defmodule ThistleTea.Game.Entity.Logic.MovementStats do
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @run_speed_fields [
    {:walk_speed, :base_walk_speed},
    {:run_speed, :base_run_speed},
    {:run_back_speed, :base_run_back_speed}
  ]

  @swim_speed_fields [
    {:swim_speed, :base_swim_speed},
    {:swim_back_speed, :base_swim_back_speed}
  ]

  @run_speed_auras [:mod_increase_speed, :mod_decrease_speed]
  @swim_speed_auras [:mod_increase_swim_speed, :mod_decrease_speed]

  def sync_aura_mods(%{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = entity) do
    movement_block =
      movement_block
      |> apply_speed_modifier(@run_speed_fields, speed_modifier(unit, @run_speed_auras))
      |> apply_speed_modifier(@swim_speed_fields, speed_modifier(unit, @swim_speed_auras))

    %{entity | movement_block: movement_block}
  end

  def sync_aura_mods(entity), do: entity

  defp speed_modifier(%Unit{auras: holders}, types) when is_list(holders) do
    holders
    |> Enum.flat_map(fn
      %Holder{auras: auras} -> auras
      _ -> []
    end)
    |> Enum.reduce(0, fn
      %Aura{type: type, amount: amount}, acc when is_integer(amount) ->
        if type in types, do: acc + amount, else: acc

      _aura, acc ->
        acc
    end)
  end

  defp speed_modifier(_unit, _types), do: 0

  defp apply_speed_modifier(%MovementBlock{} = movement_block, fields, modifier) do
    multiplier = max((100 + modifier) / 100, 0.0)

    Enum.reduce(fields, movement_block, fn {current_field, base_field}, acc ->
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
