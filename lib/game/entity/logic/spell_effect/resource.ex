defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Resource do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.PowerBurn
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}

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
        %{internal: %Internal{pet: %Pet{}}, unit: %{power5: happiness}} = state,
        %CastContext{} = context,
        spell,
        %Effect{type: :power_drain, misc_value: 4} = effect,
        _now
      )
      when is_integer(happiness) do
    drained = min(Amount.roll(spell, effect, context), max(happiness, 0))
    state = PetHappiness.change(state, -drained)
    {state, []}
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

    if effect.implicit_target_a == :caster and state.object.guid != caster_guid do
      {state, [Effects.grant_power(caster_guid, power_type, amount)]}
    else
      state = Resources.gain_power(state, power_type, amount)
      {Warrior.after_energize(state, spell, now), []}
    end
  end

  def apply(
        state,
        %CastContext{caster_guid: caster_guid} = context,
        spell,
        %Effect{type: :power_drain, misc_value: power_type} = effect,
        _now
      ) do
    if state.unit.power_type == power_type do
      available = max(current_power(state.unit, power_type) || 0, 0)
      drained = min(Amount.roll(spell, effect, context), available)
      unit = put_power(state.unit, power_type, available - drained)
      gained = trunc(drained * leech_multiplier(effect))
      {%{state | unit: unit}, [Effects.grant_power(caster_guid, 0, gained)]}
    else
      {state, []}
    end
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

  defp current_power(unit, power_type) do
    case Map.fetch(@power_fields, power_type) do
      {:ok, field} -> Map.get(unit, field)
      :error -> nil
    end
  end

  defp put_power(unit, 0, value), do: %{unit | power1: value}
  defp put_power(unit, 1, value), do: %{unit | power2: value}
  defp put_power(unit, 2, value), do: %{unit | power3: value}
  defp put_power(unit, 3, value), do: %{unit | power4: value}
  defp put_power(unit, 4, value), do: %{unit | power5: value}
  defp put_power(unit, _power_type, _value), do: unit

  defp leech_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp leech_multiplier(_effect), do: 1.0
end
