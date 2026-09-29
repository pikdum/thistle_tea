defmodule ThistleTea.Game.Core.Combat.DamageImmunity do
  @moduledoc """
  School-specific damage protection from creature templates and active damage
  and school immunity auras, with spell attributes controlling immunity bypass.
  """
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Creature.CreatureImmunity
  alias ThistleTea.Game.Core.Spell

  def immune?(entity, school, spell \\ nil) do
    not bypasses_immunity?(spell) and
      (CreatureImmunity.school?(entity, school) or damage_immune?(entity, school) or
         school_immune?(entity, school, spell))
  end

  defp damage_immune?(entity, school) do
    mask = Spell.school_mask(school)

    entity
    |> Aura.auras_of_type(:damage_immunity)
    |> Enum.any?(fn
      %Aura{misc_value: immune_mask} when is_integer(immune_mask) -> Bitwise.band(mask, immune_mask) != 0
      _aura -> false
    end)
  end

  defp school_immune?(entity, school, spell) do
    not attribute?(spell, :no_school_immunities) and Aura.school_immune?(entity, school)
  end

  defp bypasses_immunity?(spell) do
    attribute?(spell, :no_immunities) or attribute?(spell, :ignore_caster_and_target_restrictions)
  end

  defp attribute?(%Spell{} = spell, attribute), do: Spell.attribute?(spell, attribute)
  defp attribute?(_spell, _attribute), do: false
end
