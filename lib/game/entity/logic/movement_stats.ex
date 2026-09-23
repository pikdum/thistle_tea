defmodule ThistleTea.Game.Entity.Logic.MovementStats do
  @moduledoc """
  Recomputes the derived movement speeds on `movement_block` from base speed
  rates, auras, and creature health; never reads current speeds as input.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Wounded

  @walk_speed_fields [{:walk_speed, :base_walk_speed}]

  def recompute(%{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = entity) do
    slow = slow_multiplier(unit)

    movement_block =
      movement_block
      |> apply_speed_multiplier(@walk_speed_fields, 1.0)
      |> apply_speed_multiplier(
        [{:run_speed, :base_run_speed}],
        limited_multiplier(unit, run_multiplier(unit), MovementBlock.default_run_speed()) * slow *
          Wounded.speed_multiplier(entity)
      )
      |> apply_speed_multiplier([{:run_back_speed, :base_run_back_speed}], slow)
      |> apply_speed_multiplier(
        [{:swim_speed, :base_swim_speed}],
        limited_multiplier(unit, buff_multiplier(unit, :mod_increase_swim_speed), MovementBlock.default_swim_speed()) *
          slow
      )
      |> apply_speed_multiplier([{:swim_back_speed, :base_swim_back_speed}], 1.0)

    %{entity | movement_block: movement_block}
  end

  def recompute(entity), do: entity

  def sync(entity) do
    updated = recompute(entity)
    {updated, speed_change_events(entity, updated)}
  end

  defp speed_change_events(%{movement_block: %MovementBlock{} = previous}, %{movement_block: %MovementBlock{} = current}) do
    [
      {:run_speed, previous.run_speed, current.run_speed},
      {:run_back_speed, previous.run_back_speed, current.run_back_speed},
      {:swim_speed, previous.swim_speed, current.swim_speed},
      {:swim_back_speed, previous.swim_back_speed, current.swim_back_speed}
    ]
    |> Enum.flat_map(fn
      {type, old, new} when is_number(old) and is_number(new) and old != new ->
        [Effects.movement_speed_changed(new, type)]

      _ ->
        []
    end)
  end

  defp speed_change_events(_previous, _current), do: []

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

  defp limited_multiplier(unit, multiplier, base_speed) do
    limit = unit |> aura_amounts(:use_normal_movement_speed) |> Enum.max(fn -> 0 end)
    if limit > 0, do: min(multiplier, limit / base_speed), else: multiplier
  end

  defp run_multiplier(%Unit{mount_display_id: display} = unit) when is_integer(display) and display > 0 do
    buff_multiplier(unit, :mod_increase_mounted_speed) *
      max(stacking_multiplier(unit, :mod_mounted_speed_always), buff_multiplier(unit, :mod_mounted_speed_not_stack))
  end

  defp run_multiplier(unit) do
    buff_multiplier(unit, :mod_increase_speed) *
      max(stacking_multiplier(unit, :mod_speed_always), buff_multiplier(unit, :mod_speed_not_stack))
  end

  defp stacking_multiplier(unit, type) do
    unit |> aura_amounts(type) |> Enum.reduce(1.0, fn amount, acc -> acc * max(1 + amount / 100, 0.0) end)
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
        base when is_number(base) -> struct!(acc, [{current_field, base * multiplier}])
        _ -> acc
      end
    end)
  end
end
