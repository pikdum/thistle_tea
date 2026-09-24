defmodule ThistleTea.Game.Entity.Logic.CastSpeed do
  @moduledoc "Derives casting duration multipliers from independent haste and slow effects."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackSpeed
  alias ThistleTea.Game.Spell

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

  def multiplier(%Unit{auras: holders}) do
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
