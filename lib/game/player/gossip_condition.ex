defmodule ThistleTea.Game.Player.GossipCondition do
  @moduledoc """
  Evaluates player-facing gossip conditions against runtime character state.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionLogic

  @alliance_team 469
  @horde_team 67
  @alliance_races [1, 3, 4, 7]
  @horde_races [2, 5, 6, 8]

  def met?(%Character{}, nil), do: true

  def met?(%Character{} = character, %Condition{reverse?: true} = condition) do
    not evaluate(character, %{condition | reverse?: false})
  end

  def met?(%Character{} = character, %Condition{} = condition) do
    evaluate(character, condition)
  end

  defp evaluate(character, %Condition{type: :not, children: [child]}) do
    not met?(character, child)
  end

  defp evaluate(character, %Condition{type: :or, children: children}) do
    Enum.any?(children, &met?(character, &1))
  end

  defp evaluate(character, %Condition{type: :and, children: children}) do
    Enum.all?(children, &met?(character, &1))
  end

  defp evaluate(%Character{unit: %{race: race}}, %Condition{type: {:unsupported, 6}, value1: @alliance_team}) do
    race in @alliance_races
  end

  defp evaluate(%Character{unit: %{race: race}}, %Condition{type: {:unsupported, 6}, value1: @horde_team}) do
    race in @horde_races
  end

  defp evaluate(%Character{unit: %{race: race, class: class}}, %Condition{
         type: {:unsupported, 14},
         value1: race_mask,
         value2: class_mask
       }) do
    mask_matches?(race_mask, race) and mask_matches?(class_mask, class)
  end

  defp evaluate(%Character{} = character, %Condition{} = condition) do
    ConditionLogic.met?(character, condition)
  end

  defp mask_matches?(0, _value), do: true

  defp mask_matches?(mask, value) when is_integer(mask) and is_integer(value) and value > 0,
    do: (mask &&& 1 <<< (value - 1)) != 0

  defp mask_matches?(_mask, _value), do: false
end
