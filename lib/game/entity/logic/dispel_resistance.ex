defmodule ThistleTea.Game.Entity.Logic.DispelResistance do
  @moduledoc """
  Projects active dispel-resistance spell modifiers and evaluates them against
  the original aura's spell family, independently of the dispelling spell.
  """

  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers

  def projection(%{unit: %{auras: holders}}) when is_list(holders) do
    for %Holder{spell: %Spell{spell_family: family}, stacks: stacks, auras: auras} <- holders,
        is_integer(family) and family > 0,
        %Aura{type: type, misc_value: operation, amount: amount} = aura <- auras,
        type in [:add_flat_modifier, :add_pct_modifier],
        Modifiers.operation(operation) == :resist_dispel_chance,
        is_number(amount),
        do: {family, %{aura | amount: amount * max(stacks || 1, 1)}}
  end

  def projection(_entity), do: []

  def chance(projection, %Spell{spell_family: family} = spell) when is_list(projection) do
    flags = (spell.family_flags_0 || 0) ||| (spell.family_flags_1 || 0) <<< 32

    projection
    |> Enum.flat_map(fn
      {^family, %Aura{class_mask: mask} = aura} when family > 0 ->
        if is_integer(mask) and (mask &&& flags) != 0, do: [aura], else: []

      _modifier ->
        []
    end)
    |> Modifiers.value(:resist_dispel_chance, 0)
    |> max(0)
    |> min(100)
  end

  def chance(_projection, _spell), do: 0
end
