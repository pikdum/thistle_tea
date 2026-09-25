defmodule ThistleTea.Game.Entity.Logic.Shapeshift do
  @moduledoc """
  Form-transition aura removal and target compatibility. Druid forms remove
  mechanic-bearing roots and snares on entry and exit, preserving daze and
  protected crowd controls. Stance-like forms keep shapeshift-sensitive buffs.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Passive

  @cleansing_forms [1, 2, 3, 4, 5, 8, 31]
  @protected_mechanics [1, 2, 5, 8, 12, 13, 18, 20, 23, 24, 27, 30]
  @shapeshifting_cancels 0x00008000

  def interrupt_holders(previous, desired, target_guid) do
    previous_forms = forms(previous)
    current_forms = forms(desired)
    entered = current_forms -- previous_forms
    exited = previous_forms -- current_forms

    desired =
      if exited == [],
        do: desired,
        else: Enum.reject(desired, &(&1.caster_guid == target_guid and Passive.removed_on_shape_lost?(&1.spell)))

    desired =
      if Enum.any?(entered ++ exited, fn {_key, form} -> form in @cleansing_forms end),
        do: remove_movement_auras(desired),
        else: desired

    shifted_ids = for {{id, _caster, _item, _link}, form} <- entered, Spell.shapeshifted?(form), do: id

    if shifted_ids == [] do
      desired
    else
      Enum.reject(desired, &(&1.spell.id not in shifted_ids and Holder.interruptible?(&1, @shapeshifting_cancels)))
    end
  end

  def removable_spells(holders) when is_list(holders) do
    holders
    |> Enum.filter(&removable_movement_aura?/1)
    |> Enum.map(& &1.spell.id)
    |> Enum.uniq()
  end

  def validate_target(%{unit: unit}, %Spell{} = spell, :self), do: validate_form(spell, unit.shapeshift_form)

  def validate_target(_caster, %Spell{} = spell, %{shapeshift_form: form}), do: validate_form(spell, form)
  def validate_target(_caster, _spell, _target), do: :ok

  defp validate_form(%Spell{} = spell, form) do
    if Spell.shapeshifted?(form) and ((spell.aura_interrupt_flags || 0) &&& @shapeshifting_cancels) != 0 and
         Spell.aura_effects(spell) != [] and not Enum.any?(spell.effects, & &1.area_target?),
       do: {:error, :bad_targets},
       else: :ok
  end

  defp forms(holders) do
    for %Holder{auras: auras} = holder <- holders,
        %Aura{type: :mod_shapeshift, misc_value: form} <- auras,
        is_integer(form) and form > 0,
        do: {Holder.key(holder), form}
  end

  defp remove_movement_auras(holders) do
    spell_ids = removable_spells(holders)
    Enum.reject(holders, &(&1.spell.id in spell_ids))
  end

  defp removable_movement_aura?(%Holder{spell: %Spell{} = spell} = holder) do
    mechanics = [spell.mechanic | Enum.map(spell.effects, & &1.mechanic)] |> Enum.filter(&(&1 in 1..31))

    mechanics != [] and
      (Holder.has_aura_type?(holder, :mod_root) or removable_snare?(holder, mechanics))
  end

  defp removable_snare?(%Holder{spell: spell} = holder, mechanics) do
    Holder.has_aura_type?(holder, :mod_decrease_speed) and
      not Enum.any?(mechanics, &(&1 in @protected_mechanics)) and
      not (spell.spell_icon == 15 and spell.dispel_type == 0 and 11 not in mechanics)
  end
end
