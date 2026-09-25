defmodule ThistleTea.Game.Spell.Passive do
  @moduledoc "Eligibility of learned passive spells and form-bound aura lifetimes."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Environment

  def eligible?(%Spell{} = spell, form, outdoors) do
    Spell.aura_effects(spell) != [] and Environment.validate(spell, outdoors) == :ok and
      (form_eligible?(spell, form) or ordinary_passive?(spell, form))
  end

  def form_dependent?(%Spell{} = spell), do: form_mask(spell) != 0

  def removed_on_shape_lost?(%Spell{} = spell) do
    form_dependent?(spell) and not Spell.attribute?(spell, :allow_while_not_shapeshifted) and
      not Spell.attribute?(spell, :not_while_shapeshifted)
  end

  defp form_eligible?(spell, form) when is_integer(form) and form > 0 do
    (Spell.attribute?(spell, :passive) or Spell.attribute?(spell, :do_not_display)) and
      (form_mask(spell) &&& 1 <<< (form - 1)) != 0 and
      not Spell.attribute?(spell, :allow_while_not_shapeshifted)
  end

  defp form_eligible?(_spell, _form), do: false

  defp ordinary_passive?(spell, form) do
    Spell.attribute?(spell, :passive) and
      (form_mask(spell) == 0 or
         (form in [nil, 0] and Spell.attribute?(spell, :allow_while_not_shapeshifted)))
  end

  defp form_mask(%Spell{id: 24_864}), do: 1
  defp form_mask(%Spell{stances: stances}), do: stances || 0
end
