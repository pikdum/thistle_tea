defmodule ThistleTea.Game.Core.Spell.SpellEffect.Amount do
  @moduledoc """
  Rolls spell effect values and applies all-effects modifiers to their base
  amounts. Resource drains additionally use the shared outgoing and incoming
  damage bonus stages.
  """

  alias ThistleTea.Game.Core.Combat.DamageReceived
  alias ThistleTea.Game.Core.Combat.TargetDamage
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Chain
  alias ThistleTea.Game.Core.Spell.Coefficient
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Modifiers
  alias ThistleTea.Game.Core.Stats.TargetSpellPower

  def base(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context, combo_points \\ 0) do
    amount = Effect.amount(effect, Spell.level_units(spell, context.caster_level), combo_points)
    modify_base(spell, context, amount)
  end

  def modify_base(%Spell{} = spell, %CastContext{} = context, amount) do
    if Spell.attribute?(spell, :ignore_caster_modifiers),
      do: amount,
      else: Modifiers.value(context.spell_modifiers, :all_effects, amount)
  end

  def roll(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    spell
    |> base(effect, context)
    |> Chain.scale(effect, context)
    |> trunc()
  end

  def with_damage_bonuses(entity, %CastContext{} = context, %Spell{} = spell, %Effect{} = effect, base) do
    amount = outgoing_amount(entity, context, spell, effect, base)
    trunc(DamageReceived.spell_amount(entity, amount, spell, effect))
  end

  defp outgoing_amount(entity, context, spell, effect, base) do
    if Spell.custom?(spell, :fixed_damage) or Spell.attribute?(spell, :ignore_caster_modifiers) do
      Chain.scale(base, effect, context)
    else
      bonus =
        Coefficient.bonus(TargetSpellPower.benefit(entity, context, spell), spell, effect, :direct) +
          TargetDamage.spell_bonus(entity, context.target_damage, spell, effect, :direct)

      versus = max(100 + TargetDamage.bonus(entity, context.damage_done_versus), 0) / 100

      amount =
        (base + bonus) * context.damage_done_multiplier *
          context.happiness_multiplier * versus

      amount = Chain.scale(amount, effect, context)
      trunc(Modifiers.value(context.spell_modifiers, :damage, amount))
    end
  end
end
