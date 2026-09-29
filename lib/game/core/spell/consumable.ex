defmodule ThistleTea.Game.Core.Spell.Consumable do
  @moduledoc """
  Classifies recovery and lasting consumable buffs from spell data and the
  reference's elixir masks. Vanilla flasks conflict; ordinary elixirs do not
  use the later battle and guardian restrictions.
  """
  import Bitwise, only: [&&&: 2]

  @standing_cancels 0x00040000
  @retain_item_cast 0x80000000
  @allow_while_sitting 0x08000000
  @combat_interrupt 0x08
  @flask_mask 0x03
  @well_fed_mask 0x10

  def category(%{spell_class_set: 0} = row) do
    cond do
      flag?(row, :aura_interrupt_flags, @standing_cancels) -> recovery_category(row)
      flag?(row, :attributes_ex2, @retain_item_cast) -> :well_fed
      true -> nil
    end
  end

  def category(%{spell_class_set: 6, spell_icon: icon} = row) when icon in [52, 79] do
    if flag?(row, :attributes, @allow_while_sitting) and flag?(row, :interrupt_flags, @combat_interrupt),
      do: :well_fed
  end

  def category(_row), do: nil

  def elixir_category(mask) when is_integer(mask) do
    cond do
      (mask &&& @flask_mask) == @flask_mask -> :flask
      (mask &&& @well_fed_mask) != 0 -> :well_fed
      true -> nil
    end
  end

  defp recovery_category(row) do
    auras = Enum.map(0..2, &Map.get(row, :"effect_aura_#{&1}"))
    food? = Enum.any?(auras, &(&1 in [20, 84]))
    drink? = Enum.any?(auras, &(&1 in [21, 85]))

    case {food?, drink?} do
      {true, true} -> :food_and_drink
      {true, false} -> :food
      {false, true} -> :drink
      _ -> nil
    end
  end

  defp flag?(row, field, mask), do: ((Map.get(row, field) || 0) &&& mask) != 0
end
