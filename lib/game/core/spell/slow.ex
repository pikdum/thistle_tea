defmodule ThistleTea.Game.Core.Spell.Slow do
  @moduledoc """
  Exclusive simple snares and melee attack-speed penalties. Replacement
  compares the spell's base effect and full duration, independently of the
  existing holder's remaining time or caster modifiers.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect

  @apply_aura 6
  @melee_haste 138
  @decrease_speed 33
  @prevents_anim 0x00040000
  @categories [:snare, :negative_haste]

  def category(%{spell_class_set: 13}), do: nil

  def category(row) do
    cond do
      single_aura?(row, @melee_haste) and negative_aura?(row, @melee_haste) -> :negative_haste
      single_aura?(row, @decrease_speed) and not daze?(row) -> :snare
      true -> nil
    end
  end

  def blocks?(%Spell{} = existing, %Spell{exclusive_category: category} = incoming) when category in @categories do
    Spell.exclusive_with?(existing, incoming) and not replaces?(incoming, existing)
  end

  def blocks?(_existing, _incoming), do: false

  defp single_aura?(row, aura) do
    Enum.any?(0..2, &(Map.get(row, :"effect_aura_#{&1}") == aura)) and
      Enum.all?(0..2, fn index ->
        Map.get(row, :"effect_#{index}") != @apply_aura or Map.get(row, :"effect_aura_#{index}") == aura
      end)
  end

  defp negative_aura?(row, aura) do
    Enum.any?(0..2, fn index ->
      Map.get(row, :"effect_aura_#{index}") == aura and (Map.get(row, :"effect_base_points_#{index}") || 0) < 0
    end)
  end

  defp daze?(row), do: ((Map.get(row, :attributes_ex1) || 0) &&& @prevents_anim) != 0

  defp replaces?(incoming, existing) do
    Enum.any?(incoming.effects, fn
      %Effect{type: :apply_aura, aura: type, base_points: amount} when is_number(amount) ->
        Enum.any?(existing.effects, fn
          %Effect{aura: ^type, base_points: previous} when is_number(previous) ->
            stronger?(amount, previous) or
              (amount == previous and (incoming.duration_ms || 0) >= (existing.duration_ms || 0))

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  defp stronger?(amount, previous) when previous < 0, do: amount < previous
  defp stronger?(amount, previous), do: amount > previous
end
