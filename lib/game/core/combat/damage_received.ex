defmodule ThistleTea.Game.Core.Combat.DamageReceived do
  @moduledoc """
  Applies live target damage bonuses before critical hits and mitigation.
  Flat spell bonuses use the receiving effect's coefficient; magic reductions
  cannot remove more than half the incoming damage.
  """

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.AttackDamageTaken
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Coefficient
  alias ThistleTea.Game.Core.Spell.Effect

  def amount(entity, damage, school) do
    max(damage * Aura.percent_multiplier(entity, :mod_damage_percent_taken, Spell.school_mask(school)), 0)
  end

  def swing_amount(entity, damage, kind, school) do
    amount(entity, AttackDamageTaken.swing_amount(entity, damage, kind, school), school)
  end

  def spell_amount(entity, damage, %Spell{} = spell, effect \\ nil, damage_type \\ :direct, stacks \\ 1) do
    if Spell.attribute?(spell, :ignore_damage_taken_modifiers) do
      max(damage, 0)
    else
      damage = flat_amount(entity, max(damage, 0), spell, effect, damage_type, max(stacks, 1))
      amount(entity, damage, spell)
    end
  end

  defp flat_amount(entity, damage, %Spell{dmg_class: class} = spell, effect, damage_type, stacks)
       when class in [2, 3] do
    AttackDamageTaken.spell_amount(entity, damage, spell, effect, damage_type, stacks)
  end

  defp flat_amount(entity, damage, spell, effect, damage_type, stacks) do
    flat = Aura.flat_modifier(entity, :mod_damage_taken, Spell.school_mask(spell))
    flat = flat * coefficient(spell, effect, damage_type) * stacks
    damage + max(flat, -damage / 2)
  end

  defp coefficient(%Spell{} = spell, %Effect{} = effect, damage_type) do
    if Spell.custom?(spell, :fixed_damage), do: 0, else: Coefficient.value(spell, effect, damage_type)
  end

  defp coefficient(_spell, nil, _damage_type), do: 0
end
