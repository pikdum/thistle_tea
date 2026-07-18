defmodule ThistleTea.Game.Entity.Logic.MovementStats do
  @moduledoc """
  Recomputes the derived movement speeds on `movement_block` from base speed
  rates and movement-modifying auras; never reads current speeds as input.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @walk_speed_fields [{:walk_speed, :base_walk_speed}]

  @run_speed_fields [
    {:run_speed, :base_run_speed},
    {:run_back_speed, :base_run_back_speed}
  ]

  @swim_speed_fields [
    {:swim_speed, :base_swim_speed},
    {:swim_back_speed, :base_swim_back_speed}
  ]

  def recompute(%{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = entity) do
    slow = slow_multiplier(unit)

    movement_block =
      movement_block
      |> apply_speed_multiplier(@walk_speed_fields, 1.0)
      |> apply_speed_multiplier(@run_speed_fields, buff_multiplier(unit, :mod_increase_speed) * slow)
      |> apply_speed_multiplier(@swim_speed_fields, buff_multiplier(unit, :mod_increase_swim_speed) * slow)

    %{entity | movement_block: movement_block}
  end

  def recompute(entity), do: entity

  def set_run_speed_rate(%{movement_block: %MovementBlock{} = movement_block} = entity, rate) when is_number(rate) do
    movement_block = %{movement_block | base_run_speed: rate * MovementBlock.default_run_speed()}
    recompute(%{entity | movement_block: movement_block})
  end

  defp buff_multiplier(%Unit{} = unit, type) do
    best =
      unit
      |> aura_amounts(type)
      |> Enum.filter(&(&1 > 0))
      |> Enum.max(fn -> 0 end)

    (100 + best) / 100
  end

  defp slow_multiplier(%Unit{} = unit) do
    worst =
      unit
      |> aura_amounts(:mod_decrease_speed)
      |> Enum.filter(&(&1 < 0))
      |> Enum.min(fn -> 0 end)

    max((100 + worst) / 100, 0.0)
  end

  defp aura_amounts(%Unit{auras: holders}, type) when is_list(holders) do
    for %Holder{auras: auras} <- holders,
        %Aura{type: ^type, amount: amount} <- auras,
        is_integer(amount),
        do: amount
  end

  defp aura_amounts(_unit, _type), do: []

  defp apply_speed_multiplier(%MovementBlock{} = movement_block, fields, multiplier) do
    Enum.reduce(fields, movement_block, fn {current_field, base_field}, acc ->
      case Map.get(acc, base_field) do
        base when is_number(base) -> Map.put(acc, current_field, base * multiplier)
        _ -> acc
      end
    end)
  end
end
