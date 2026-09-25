defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Resource do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.PowerBurn
  alias ThistleTea.Game.Entity.Logic.PowerLeech
  alias ThistleTea.Game.Entity.Logic.PowerRestoration
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def apply(state, %CastContext{caster_type: :player} = context, spell, %Effect{type: :add_combo_points} = effect, _now) do
    retention = if context.combo_retention_spell, do: {context.combo_retention_spell, context}

    award = %Effects.AddComboPoints{
      source_guid: context.caster_guid,
      target_guid: state.object.guid,
      amount: Amount.roll(spell, effect, context),
      retention: retention
    }

    {state, [award]}
  end

  def apply(
        state,
        %CastContext{caster_guid: caster_guid} = context,
        spell,
        %Effect{type: :energize, misc_value: power_type} = effect,
        now
      )
      when is_integer(power_type) and power_type >= 0 do
    amount = Amount.roll(spell, effect, context)
    target_guid = if effect.implicit_target_a == :caster, do: caster_guid, else: state.object.guid

    grant = %Effects.GrantPower{
      source_guid: caster_guid,
      target_guid: target_guid,
      misc_value: power_type,
      amount: amount,
      spell: spell
    }

    if state.object.guid == target_guid do
      PowerRestoration.apply(state, grant, now)
    else
      {state, [grant]}
    end
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :power_drain} = effect, _now) do
    PowerLeech.direct(state, context, spell, effect)
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :power_burn} = effect, now) do
    PowerBurn.apply(
      state,
      context,
      spell,
      Amount.roll(spell, effect, context),
      effect,
      now
    )
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :inebriate} = effect, now) do
    {Intoxication.drink(state, Amount.roll(spell, effect, context), now), []}
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}
end
