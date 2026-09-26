defmodule ThistleTea.Game.Entity.Logic.Effects.RandomChoice do
  @moduledoc """
  Weighted alternatives of effect lists. The owner boundary supplies a roll;
  selection remains deterministic and preserves the chosen effects' order.
  """

  @enforce_keys [:choices]
  defstruct [:choices]

  def total_weight(%__MODULE__{choices: choices}) do
    Enum.reduce(choices, 0, fn {weight, _effects}, total -> total + weight end)
  end

  def select(%__MODULE__{choices: choices}, roll) when is_integer(roll) and roll > 0 do
    select_choice(choices, roll)
  end

  defp select_choice([{weight, effects} | _rest], roll) when roll <= weight, do: effects
  defp select_choice([{weight, _effects} | rest], roll), do: select_choice(rest, roll - weight)
  defp select_choice([], _roll), do: []
end
