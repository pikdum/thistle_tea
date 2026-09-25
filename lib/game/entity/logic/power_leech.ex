defmodule ThistleTea.Game.Entity.Logic.PowerLeech do
  @moduledoc """
  Drains the victim's active resource and delivers leech gains to the caster's
  owner. Periodic leech threat uses the gain after the caster clamps it, while
  combat logs describe the resource actually removed from the victim.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  def direct(entity, %CastContext{} = context, %Spell{} = spell, %Effect{} = effect) do
    amount = direct_amount(entity, context, spell, effect)
    base = if effect.multiple_value in [nil, 0, 0.0], do: 1.0, else: effect.multiple_value
    multiplier = max(Modifiers.value(context.spell_modifiers, :multiple_value, base), 0.0)
    drain(entity, context, spell, effect.misc_value, amount, multiplier, false)
  end

  def periodic(entity, %CastContext{} = context, %Spell{} = spell, aura) do
    if entity.unit.power_type == aura.misc_value do
      drain(entity, context, spell, aura.misc_value, max(aura.amount, 0), aura.multiple_value || 0.0, true)
    else
      {entity, []}
    end
  end

  defp drain(entity, context, spell, power, amount, multiplier, periodic?)
       when power in 0..4 and is_number(amount) and amount >= 0 do
    if Death.alive?(entity) and drainable?(entity, power) do
      {entity, drained} = consume(entity, power, amount)

      leech = %Effects.LeechPower{
        source_guid: context.caster_guid,
        target_guid: entity.object.guid,
        spell: spell,
        power_type: power,
        amount: drained,
        multiplier: max(multiplier, 0.0),
        periodic?: periodic?,
        threat_multiplier: SpellThreat.multiplier(context)
      }

      if periodic? or (power == 0 and entity.object.guid != context.caster_guid) do
        {entity, [leech]}
      else
        {entity, [log(%{leech | multiplier: 0.0})]}
      end
    else
      {entity, []}
    end
  end

  defp drain(entity, _context, _spell, _power, _amount, _multiplier, _periodic?), do: {entity, []}

  def restore(caster, leech, rounding_roll \\ 0.5)

  def restore(%{object: %{guid: guid}} = caster, %Effects.LeechPower{source_guid: guid} = leech, rounding_roll) do
    multiplier =
      if Death.alive?(caster) and Resources.max_power(caster, leech.power_type) > 0,
        do: transfer_multiplier(caster, leech),
        else: 0.0

    previous = Resources.current_power(caster, leech.power_type)
    gain = restored_amount(leech, multiplier, rounding_roll)
    caster = Resources.gain_power(caster, leech.power_type, gain)
    gained = Resources.current_power(caster, leech.power_type) - previous
    events = [log(%{leech | multiplier: multiplier}) | threat_events(leech, gained)]
    {caster, events}
  end

  def restore(caster, _leech, _rounding_roll), do: {caster, []}

  defp restored_amount(%Effects.LeechPower{periodic?: true, amount: amount}, multiplier, _roll),
    do: trunc(amount * multiplier)

  defp restored_amount(%Effects.LeechPower{amount: amount}, multiplier, roll) do
    gain = amount * multiplier
    trunc(gain) + if(roll < gain - trunc(gain), do: 1, else: 0)
  end

  defp transfer_multiplier(caster, %Effects.LeechPower{periodic?: true} = leech),
    do: max(Modifiers.value(caster, leech.spell, :multiple_value, leech.multiplier), 0.0)

  defp transfer_multiplier(_caster, %Effects.LeechPower{} = leech), do: leech.multiplier

  defp threat_events(%Effects.LeechPower{periodic?: true} = leech, gained) when gained > 0 do
    [
      %Effects.AddThreat{
        source_guid: leech.source_guid,
        target_guid: leech.target_guid,
        amount: gained * 0.5 * leech.threat_multiplier
      }
    ]
  end

  defp threat_events(_leech, _gained), do: []

  defp log(%Effects.LeechPower{periodic?: true} = leech) do
    Effects.periodic_aura_log(leech.source_guid, leech.target_guid, leech.spell, :periodic_mana_leech, leech.amount,
      misc_value: leech.power_type,
      multiplier: leech.multiplier
    )
  end

  defp log(%Effects.LeechPower{} = leech) do
    %Effects.SpellPowerDrain{
      source_guid: leech.source_guid,
      target_guid: leech.target_guid,
      spell_id: leech.spell.id,
      power_type: leech.power_type,
      amount: leech.amount,
      multiplier: leech.multiplier
    }
  end

  defp drainable?(%{internal: %{pet: %Pet{}}}, 4), do: true
  defp drainable?(%{unit: %{power_type: power}}, power) when power in 0..3, do: true
  defp drainable?(_entity, _power), do: false

  defp consume(entity, 4, amount) do
    drained = min(trunc(amount), max(Resources.current_power(entity, 4), 0))
    {PetHappiness.change(entity, -drained), drained}
  end

  defp consume(entity, power, amount), do: Resources.consume_power(entity, power, amount)

  defp direct_amount(entity, context, spell, effect) do
    base = Effect.roll(effect, Spell.level_units(spell, context.caster_level))
    if base < 0, do: base, else: Amount.with_damage_bonuses(entity, context, spell, effect, base)
  end
end
