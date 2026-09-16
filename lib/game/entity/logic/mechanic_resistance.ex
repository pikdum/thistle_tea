defmodule ThistleTea.Game.Entity.Logic.MechanicResistance do
  @moduledoc """
  Resistance to spell mechanics such as stun, root, and fear.

  Whole-spell resistance participates in the spell's hit roll. Individual
  effects roll separately only when their mechanic differs from the spell's,
  following VMangos SpellCaster and Unit::IsEffectResist.
  """
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def projection(entity), do: Aura.misc_amounts(entity, :mechanic_resistance)

  def chance(pairs, mechanic) when is_list(pairs) and is_integer(mechanic) and mechanic > 0 do
    Enum.reduce(pairs, 0, fn
      {^mechanic, amount}, total -> total + amount
      _pair, total -> total
    end)
  end

  def chance(_pairs, _mechanic), do: 0

  def effect_resisted?(pairs, %Spell{mechanic: spell_mechanic}, %Effect{mechanic: mechanic}, roll)
      when is_integer(mechanic) and mechanic > 0 and mechanic != spell_mechanic and is_integer(roll) do
    roll < chance(pairs, mechanic)
  end

  def effect_resisted?(_pairs, _spell, _effect, _roll), do: false
end
