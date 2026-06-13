defmodule ThistleTea.Game.Entity.Logic.Aura.Periodic do
  @moduledoc """
  Ticks periodic auras (damage, heal, leech, trigger-spell) when their
  next-tick time comes due, expires elapsed holders afterwards, and reports
  the earliest upcoming tick or expiry for tick scheduling.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Lifecycle
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  def tick(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    entity
    |> tick_periodics(now)
    |> then(fn {entity, events} ->
      {entity, expire_events} = Lifecycle.expire_due(entity, now)
      {entity, events ++ expire_events}
    end)
  end

  def tick(entity, _now), do: {entity, []}

  def next_event_at(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.flat_map(&holder_event_times/1)
    |> Enum.min(fn -> nil end)
  end

  def next_event_at(_entity), do: nil

  defp tick_periodics(%{unit: %Unit{auras: holders}} = entity, now) do
    result =
      Enum.reduce_while(holders, {entity, [], []}, fn holder, {ent, acc, events} ->
        {ent, new_holder, holder_events} = tick_holder(ent, holder, now)
        events = events ++ holder_events

        if Core.dead?(ent) do
          {:halt, {ent, :died, events}}
        else
          {:cont, {ent, [new_holder | acc], events}}
        end
      end)

    case result do
      {entity, :died, events} ->
        {entity, events}

      {entity, acc, events} ->
        new_holders =
          acc
          |> Enum.reverse()
          |> Enum.filter(&holder_still_present?(entity, &1))

        entity =
          if new_holders == holders do
            entity
          else
            %{entity | unit: %{entity.unit | auras: new_holders}}
          end

        {entity, events}
    end
  end

  defp holder_still_present?(%{unit: %Unit{auras: current}}, %Holder{spell: %Spell{id: id}, caster_guid: caster}) do
    Enum.any?(current, &Holder.same_source?(&1, id, caster))
  end

  defp tick_holder(entity, %Holder{auras: auras} = holder, now) do
    {entity, new_auras, events} =
      Enum.reduce(auras, {entity, [], []}, fn aura, {ent, acc, events} ->
        {ent, new_aura, aura_events} = tick_aura(ent, holder, aura, now)
        {ent, [new_aura | acc], events ++ aura_events}
      end)

    {entity, %{holder | auras: Enum.reverse(new_auras)}, events}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_damage, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    damage = aura.amount
    entity = Core.take_damage(entity, damage, now, school: holder.spell.school)

    event =
      Event.spell_damage(holder.caster_guid, entity.object.guid, holder.spell, damage, periodic?: true)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event]}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_heal, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    entity = Core.heal(entity, aura.amount)
    event = Event.periodic_aura_log(holder.caster_guid, entity.object.guid, holder.spell, :periodic_heal, aura.amount)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event]}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_energize, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    misc_value = power_type(aura.misc_value)
    entity = restore_power(entity, misc_value, aura.amount)

    event =
      Event.periodic_aura_log(holder.caster_guid, entity.object.guid, holder.spell, :periodic_energize, aura.amount,
        misc_value: misc_value
      )

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event]}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :mod_regen, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    event =
      case missing_health(entity) do
        missing when missing > 0 ->
          Event.periodic_aura_log(
            holder.caster_guid,
            entity.object.guid,
            holder.spell,
            :periodic_heal,
            min(aura.amount, missing)
          )

        _missing ->
          nil
      end

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, compact_events([event])}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :mod_power_regen, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    misc_value = power_type(aura.misc_value)

    event =
      case missing_power(entity, misc_value) do
        missing when missing > 0 ->
          Event.periodic_aura_log(
            holder.caster_guid,
            entity.object.guid,
            holder.spell,
            :periodic_energize,
            min(aura.amount, missing),
            misc_value: misc_value
          )

        _missing ->
          nil
      end

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, compact_events([event])}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_leech, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    damage = aura.amount
    entity = Core.take_damage(entity, damage, now, school: holder.spell.school)

    events = [
      Event.spell_damage(holder.caster_guid, entity.object.guid, holder.spell, damage, periodic?: true)
      | leech_heal_events(holder, entity, damage, aura)
    ]

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, events}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_trigger_spell, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    events =
      case aura.trigger_spell_id do
        spell_id when is_integer(spell_id) and spell_id > 0 ->
          [Event.trigger_spell(holder.caster_guid, holder.caster_level, entity.object.guid, spell_id)]

        _ ->
          []
      end

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, events}
  end

  defp tick_aura(entity, _holder, aura, _now), do: {entity, aura, []}

  defp leech_heal_events(%Holder{caster_guid: caster_guid}, %{object: %{guid: owner_guid}}, damage, %Aura{} = aura)
       when is_integer(caster_guid) and caster_guid != owner_guid and damage > 0 do
    multiplier = if is_number(aura.multiple_value) and aura.multiple_value > 0, do: aura.multiple_value, else: 1.0
    [Event.heal_entity(caster_guid, trunc(damage * multiplier))]
  end

  defp leech_heal_events(_holder, _entity, _damage, _aura), do: []

  defp restore_power(entity, 0, amount), do: Core.restore_mana(entity, amount)
  defp restore_power(entity, _power_type, _amount), do: entity

  defp missing_health(%{unit: %Unit{health: health, max_health: max_health}})
       when is_integer(health) and is_integer(max_health) do
    max(max_health - health, 0)
  end

  defp missing_health(_entity), do: 0

  defp missing_power(%{unit: %Unit{power_type: power_type, power1: power, max_power1: max_power}}, 0)
       when power_type == 0 and is_integer(power) and is_integer(max_power) do
    max(max_power - power, 0)
  end

  defp missing_power(_entity, _power_type), do: 0

  defp compact_events(events), do: Enum.reject(events, &is_nil/1)

  defp power_type(value) when is_integer(value) and value >= 0, do: value
  defp power_type(_value), do: 0

  defp advance_tick(last_tick, amplitude_ms, now) when is_integer(amplitude_ms) and amplitude_ms > 0 do
    next = last_tick + amplitude_ms
    if next > now, do: next, else: advance_tick(next, amplitude_ms, now)
  end

  defp advance_tick(_last_tick, _amplitude_ms, now), do: now + 1_000

  defp holder_event_times(%Holder{} = holder) do
    tick_times = Enum.flat_map(holder.auras, &aura_tick_time/1)

    if is_integer(holder.expires_at) and holder.expires_at != -1 do
      [holder.expires_at | tick_times]
    else
      tick_times
    end
  end

  defp aura_tick_time(%Aura{next_tick_at: at}) when is_integer(at), do: [at]
  defp aura_tick_time(_), do: []
end
