defmodule ThistleTea.Game.Entity.Logic.HealingReceived do
  @moduledoc """
  Applies healing-received percentages from current auras. The strongest
  reduction and strongest increase combine multiplicatively; stacks within
  a holder contribute to that holder's strength. These modifiers are not
  school-specific and are evaluated when healing lands, including HoT ticks.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core

  def amount(entity, amount) when is_number(amount) do
    {reduction, increase} = extremes(entity)
    max(trunc(amount * max(100 + reduction, 0) / 100 * (100 + increase) / 100), 0)
  end

  def heal(entity, amount) do
    if Core.dead?(entity), do: entity, else: Core.heal(entity, amount(entity, amount))
  end

  defp extremes(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.reduce(holders, {0, 0}, fn %Holder{auras: auras, stacks: stacks}, limits ->
      Enum.reduce(auras, limits, fn
        %Aura{type: :mod_healing_pct, amount: amount}, {low, high} when is_number(amount) ->
          value = amount * max(stacks || 1, 1)
          {min(low, value), max(high, value)}

        _aura, limits ->
          limits
      end)
    end)
  end

  defp extremes(_entity), do: {0, 0}
end
