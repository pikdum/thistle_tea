defmodule ThistleTea.Game.Entity.Logic.Mage do
  @moduledoc """
  Mage-specific spell rules mirrored from the VMangos mage spell scripts:
  the Cold Snap frost-school cooldown filter.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell

  @spell_family 3

  def frost_cooldown?(%Spell{spell_family: @spell_family} = spell) do
    (Spell.school_mask(spell) &&& Spell.school_mask(:frost)) != 0
  end

  def frost_cooldown?(_spell), do: false
end
