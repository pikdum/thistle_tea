defmodule ThistleTea.Game.Spell.SharedDamage do
  @moduledoc """
  Divides designated effect amounts among their launch-time recipients before
  damage bonuses and mitigation. Misses retain their share of the damage.
  """

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  def required?(%Spell{} = spell), do: Semantics.rules(spell).shared_damage_effects != []

  def divide(amount, %Spell{} = spell, %Effect{index: index}, %CastContext{effect_target_counts: counts}) do
    if index in Semantics.rules(spell).shared_damage_effects,
      do: div(trunc(amount), max(Map.get(counts, index, 1), 1)),
      else: amount
  end
end
