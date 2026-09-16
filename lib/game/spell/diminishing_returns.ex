defmodule ThistleTea.Game.Spell.DiminishingReturns do
  @moduledoc """
  Vanilla crowd-control groups, following VMangos SpellEntry. Spell and effect
  mechanics share a group; aura-triggered stuns and roots use separate groups.
  Duration-only restrictions and heartbeat breaks are separate from diminishing
  returns and do not advance these groups.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell

  @mechanic_groups [
    {12, :controlled_stun},
    {10, :sleep},
    {17, :polymorph},
    {7, :controlled_root},
    {5, :fear},
    {1, :charm},
    {9, :silence},
    {3, :disarm},
    {13, :freeze},
    {14, :knockout},
    {30, :knockout},
    {18, :banish},
    {24, :horror}
  ]

  def group(spell, triggered_by_aura? \\ false)

  def group(%Spell{spell_family: 8, family_flags_0: flags}, _) when (flags &&& 0x00200000) != 0, do: :kidney_shot

  def group(%Spell{spell_family: 8, family_flags_0: flags}, _) when (flags &&& 0x01000000) != 0, do: nil
  def group(%Spell{spell_family: 9, family_flags_0: flags}, _) when (flags &&& 0x8) != 0, do: :freeze

  def group(%Spell{spell_family: 5, family_flags_0: flags, mechanic: 5}, _) when (flags &&& 0x80000000) != 0,
    do: :warlock_fear

  def group(%Spell{spell_family: 5, id: 6358}, _), do: :warlock_fear
  def group(%Spell{spell_family: 5, family_flags_0: flags}, _) when (flags &&& 0x80000000) != 0, do: nil
  def group(%Spell{spell_family: 4, family_flags_0: flags}, _) when (flags &&& 0x2) != 0, do: nil

  def group(%Spell{spell_family: 11, family_flags_0: flags}, _) when (flags &&& 0x80000000) != 0, do: :controlled_root

  def group(%Spell{spell_family: 3, spell_visual: 4325}, _), do: nil
  def group(%Spell{spell_family: 0, id: id}, _) when id in [12_355, 18_093], do: :triggered_stun
  def group(%Spell{id: id}, _) when id in [7922, 20_253, 20_614, 20_615], do: :controlled_stun

  def group(%Spell{mechanic: mechanic, effects: effects}, triggered_by_aura?) do
    mechanics = [mechanic | Enum.map(effects, & &1.mechanic)]

    @mechanic_groups
    |> Enum.find_value(fn {mechanic, group} -> if mechanic in mechanics, do: group end)
    |> triggered_group(triggered_by_aura?)
  end

  def scope(nil), do: :none
  def scope(group) when group in [:controlled_stun, :triggered_stun, :kidney_shot], do: :all
  def scope(_group), do: :pvp

  defp triggered_group(:controlled_stun, true), do: :triggered_stun
  defp triggered_group(:controlled_root, true), do: :triggered_root
  defp triggered_group(group, _triggered_by_aura?), do: group
end
