defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Resource do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}

  def apply(state, %CastContext{}, _spell, %Effect{type: :add_combo_points}, _now), do: {state, []}

  def apply(
        %{internal: %Internal{pet: %Pet{}}, unit: %{power5: happiness} = unit} = state,
        %CastContext{} = context,
        spell,
        %Effect{type: :power_drain, misc_value: 4} = effect,
        _now
      )
      when is_integer(happiness) do
    drained = min(Amount.roll(spell, effect, context), max(happiness, 0))
    state = %{state | unit: %{unit | power5: happiness - drained}} |> Core.mark_broadcast_update()
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

  def apply(state, %CastContext{}, _spell, %Effect{type: :power_burn, misc_value: power_type}, _now)
      when state.unit.power_type != power_type do
    {state, []}
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :power_burn} = effect, now) do
    drained = min(Amount.roll(spell, effect, context), max(state.unit.power1 || 0, 0))

    if drained > 0 do
      state =
        %{state | unit: %{state.unit | power1: state.unit.power1 - drained}}
        |> Core.mark_broadcast_update()

      damage = trunc(drained * burn_multiplier(effect))
      state = Core.take_damage(state, damage, now, [school: school_atom(spell)] ++ damage_source_opts(context))
      event = Effects.spell_damage(context.caster_guid, state.object.guid, spell, damage)

      {state, [event]}
    else
      {state, []}
    end
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

  defp burn_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp burn_multiplier(_effect), do: 1.0

  defp leech_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp leech_multiplier(_effect), do: 1.0

  defp school_atom(%Spell{school: school}) when is_atom(school), do: school

  defp school_atom(%Spell{} = spell),
    do: Enum.at([:physical, :holy, :fire, :nature, :frost, :shadow, :arcane], Spell.school_index(spell), :physical)

  defp damage_source_opts(%CastContext{} = context) do
    [
      source: context.caster_guid,
      source_owner: context.caster_owner_guid,
      reflected_by: context.reflected_by_guid
    ]
  end
end
