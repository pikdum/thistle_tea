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

  def recompute(%{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = entity) do
    movement_block =
      movement_block
      |> apply_speed_modifier(@run_speed_fields, speed_modifier(unit, @run_speed_auras))
      |> apply_speed_modifier(@swim_speed_fields, speed_modifier(unit, @swim_speed_auras))

    %{entity | movement_block: movement_block}
  end

  def recompute(entity), do: entity

  def set_run_speed_rate(%{movement_block: %MovementBlock{} = movement_block} = entity, rate) when is_number(rate) do
    movement_block = %{movement_block | base_run_speed: rate * MovementBlock.default_run_speed()}
    recompute(%{entity | movement_block: movement_block})
  end

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
      case Map.get(acc, base_field) do
        base when is_number(base) -> Map.put(acc, current_field, base * multiplier)
        _ -> acc
      end
    end)
  end
end
