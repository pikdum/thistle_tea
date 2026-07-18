defmodule ThistleTea.Game.Entity.Logic.Rogue do
  @moduledoc """
  Rogue-specific spell rules mirrored from the VMangos rogue spell scripts:
  family-mask predicates for stealth, Vanish, Eviscerate, and Blade Flurry.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell

  @spell_family 8
  @stealth_family_mask 0x00400000
  @misc_family_mask 0x40000000

  def spell_family, do: @spell_family

  def rogue_spell?(%Spell{spell_family: @spell_family}), do: true
  def rogue_spell?(_spell), do: false

  def stealth?(%Spell{} = spell), do: family_flag?(spell, @stealth_family_mask)
  def stealth?(_spell), do: false

  def vanish?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_rogue_vanish")
  def vanish?(_spell), do: false

  def eviscerate?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_rogue_eviscerate")
  def eviscerate?(_spell), do: false

  def blade_flurry?(%Spell{effects: effects} = spell) do
    family_flag?(spell, @misc_family_mask) and
      Enum.any?(effects, &(&1.type in [:apply_aura, :apply_area_aura] and &1.aura == :mod_melee_haste))
  end

  def blade_flurry?(_spell), do: false

  defp family_flag?(%Spell{spell_family: @spell_family, family_flags_0: flags}, mask) when is_integer(flags),
    do: (flags &&& mask) != 0

  defp family_flag?(_spell, _mask), do: false
end
