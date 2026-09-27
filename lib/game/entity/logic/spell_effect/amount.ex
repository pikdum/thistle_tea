defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Amount do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.DamageReceived
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Entity.Logic.TargetSpellPower
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Chain
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  def roll(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    effect
    |> Effect.roll(Spell.level_units(spell, context.caster_level))
    |> Chain.scale(effect, context)
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
        (base + bonus) * context.effect_damage_multiplier * context.damage_done_multiplier *
          context.happiness_multiplier * versus

      Chain.scale(trunc(amount), effect, context)
    end
  end
end
