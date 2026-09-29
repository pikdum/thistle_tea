defmodule ThistleTea.Game.Core.Stats.CastSpeed do
  @moduledoc "Derives casting duration multipliers from independent haste and slow effects."

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Stats.AttackSpeed

  def recompute(%Unit{} = unit), do: %{unit | mod_cast_speed: multiplier(unit)}

  def multiplier(%Unit{} = unit, %Spell{} = spell) do
    if Spell.attribute?(spell, :ability) or Spell.attribute?(spell, :tradeskill) do
      if Spell.ranged_ability?(spell) and not Spell.auto_repeat?(spell),
        do: AttackSpeed.multiplier(unit, :ranged),
        else: 1.0
    else
      multiplier(unit)
    end
  end

  defp multiplier(%Unit{auras: holders}) do
    for %Holder{} = holder <- holders || [],
        %Aura{type: :mod_casting_speed, amount: amount} <- holder.auras,
        is_number(amount),
        reduce: 1.0 do
      multiplier -> multiplier * factor(amount * max(holder.stacks || 1, 1))
    end
  end

  defp factor(amount) when amount >= 0, do: 100 / (100 + amount)
  defp factor(amount), do: (100 - amount) / 100
end
