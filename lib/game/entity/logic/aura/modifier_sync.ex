defmodule ThistleTea.Game.Entity.Logic.Aura.ModifierSync do
  @moduledoc """
  Derives the client spell-modifier table from aura holders and emits absolute
  totals for entries whose value changed.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event

  @modifier_types %{add_flat_modifier: :flat, add_pct_modifier: :pct}
  @effect_indexes 0..63

  def events(previous_holders, holders) when is_list(previous_holders) and is_list(holders) do
    previous = totals(previous_holders)
    current = totals(holders)

    previous
    |> Map.keys()
    |> Kernel.++(Map.keys(current))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      previous_value = Map.get(previous, key, 0)
      current_value = Map.get(current, key, 0)

      if previous_value == current_value do
        []
      else
        {modifier_type, effect_index, operation} = key
        [Event.spell_modifier(modifier_type, effect_index, operation, current_value)]
      end
    end)
  end

  def events(_previous_holders, _holders), do: []

  def totals(holders) when is_list(holders) do
    Enum.reduce(holders, %{}, &add_holder/2)
  end

  def totals(_holders), do: %{}

  defp add_holder(%Holder{auras: auras} = holder, totals) do
    Enum.reduce(auras, totals, &add_aura(&1, holder_stacks(holder), &2))
  end

  defp add_aura(%Aura{type: type, amount: amount, class_mask: mask, misc_value: operation}, stacks, totals)
       when is_map_key(@modifier_types, type) and is_number(amount) and is_integer(mask) and mask > 0 and
              is_integer(operation) do
    modifier_type = Map.fetch!(@modifier_types, type)
    value = round(amount * stacks)

    Enum.reduce(@effect_indexes, totals, fn effect_index, acc ->
      if (mask &&& 1 <<< effect_index) == 0 do
        acc
      else
        Map.update(acc, {modifier_type, effect_index, operation}, value, &(&1 + value))
      end
    end)
  end

  defp add_aura(_aura, _stacks, totals), do: totals

  defp holder_stacks(%Holder{stacks: stacks}) when is_integer(stacks) and stacks > 1, do: stacks
  defp holder_stacks(_holder), do: 1
end
