defmodule ThistleTea.Game.Spell.AbsorbBonus do
  @moduledoc """
  Snapshots the vanilla ten-percent caster bonus for Power Word: Shield and
  elemental wards. Shield base modifiers apply before this bonus; Mana Shield
  and unrelated absorbs do not scale with spell power.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  @priest 6
  @mage 3
  @warlock 5
  @power_word_shield 0x1
  @elemental_wards 0x108

  def value(%Spell{} = spell, %Effect{aura: :school_absorb}, %CastContext{} = context) do
    max(benefit(spell, context), 0) * 0.1 * Coefficient.level_penalty(spell)
  end

  def value(_spell, _effect, _context), do: 0

  defp benefit(%Spell{spell_family: @priest, family_flags_0: flags}, context) when (flags &&& @power_word_shield) != 0,
    do: context.healing_bonus || 0

  defp benefit(%Spell{spell_family: @mage, family_flags_0: flags} = spell, context)
       when (flags &&& @elemental_wards) != 0, do: school_power(spell, context)

  defp benefit(%Spell{spell_family: family, school: :shadow, spell_icon: 207, category: 56} = spell, context)
       when family in [0, @warlock], do: school_power(spell, context)

  defp benefit(_spell, _context), do: 0

  defp school_power(%Spell{school: school}, %CastContext{spell_damage_bonus: bonuses}) do
    Map.get(bonuses || %{}, school, 0)
  end
end
