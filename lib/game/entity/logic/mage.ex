defmodule ThistleTea.Game.Entity.Logic.Mage do
  @moduledoc """
  Mage-specific spell rules mirrored from the VMangos mage spell scripts:
  the Cold Snap frost-school cooldown filter and ward reflection talents.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @spell_family 3
  @warding_talents %{
    11_094 => 0x8,
    13_043 => 0x8,
    11_189 => 0x100,
    28_332 => 0x100
  }

  def frost_cooldown?(%Spell{spell_family: @spell_family} = spell) do
    (Spell.school_mask(spell) &&& Spell.school_mask(:frost)) != 0
  end

  def frost_cooldown?(_spell), do: false

  def ward_reflect_chance(%{internal: %{spellbook: spellbook}}, %Spell{
        spell_family: @spell_family,
        family_flags_0: family_flags
      })
      when is_map(spellbook) and is_integer(family_flags) do
    spellbook
    |> Map.values()
    |> Enum.flat_map(&warding_chance(&1, family_flags))
    |> Enum.max(fn -> 0 end)
  end

  def ward_reflect_chance(_caster, _spell), do: 0

  defp warding_chance(%Spell{id: id, effects: effects}, family_flags) when is_map_key(@warding_talents, id) do
    if (Map.fetch!(@warding_talents, id) &&& family_flags) == 0 do
      []
    else
      for %Effect{type: :dummy} = effect <- effects, do: Effect.damage_roll(effect)
    end
  end

  defp warding_chance(_spell, _family_flags), do: []
end
