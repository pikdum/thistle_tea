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
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.Threat
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
    {entity, damage, log_opts} = apply_periodic_damage(entity, holder, aura.amount, now)

    event =
      Event.spell_damage(holder.caster_guid, entity.object.guid, holder.spell, damage, log_opts)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event]}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_heal, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    threat_events = Threat.heal_threat_events(entity, holder.caster_guid, aura.amount)
    entity = Core.heal(entity, aura.amount)
    event = Event.periodic_aura_log(holder.caster_guid, entity.object.guid, holder.spell, :periodic_heal, aura.amount)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event | threat_events]}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_energize, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    {entity, events} = apply_energize(entity, holder, power_type(aura.misc_value), aura.amount)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, events}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_leech, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    {entity, damage, log_opts} = apply_periodic_damage(entity, holder, aura.amount, now)

    events = [
      Event.spell_damage(holder.caster_guid, entity.object.guid, holder.spell, damage, log_opts)
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

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  defp apply_periodic_damage(entity, %Holder{} = holder, amount, now) do
    school = school_atom(holder.spell)
    caster_level = if is_integer(holder.caster_level) and holder.caster_level > 0, do: holder.caster_level, else: 1
    resisted = periodic_resisted_amount(entity, amount, school, caster_level)
    damage = amount - resisted

    {entity, absorbed} = Core.take_damage_with_absorb(entity, damage, now, school: school, source: holder.caster_guid)

    {entity, damage, [periodic?: true, resisted: resisted, absorbed: absorbed]}
  end

  defp periodic_resisted_amount(_entity, damage, _school, _caster_level) when damage <= 0, do: 0
  defp periodic_resisted_amount(_entity, _damage, :physical, _caster_level), do: 0

  defp periodic_resisted_amount(%{unit: %Unit{} = unit} = entity, damage, school, caster_level) do
    resistance = Map.get(unit, :"#{school}_resistance") || 0
    target_creature? = not is_map(Map.get(entity, :player))
    level_diff = (unit.level || 1) - caster_level

    SpellResist.resisted_amount(damage, resistance, caster_level,
      target_creature?: target_creature?,
      level_diff: level_diff,
      dot?: true
    )
  end

  defp school_atom(%Spell{school: school}) when is_atom(school) and not is_nil(school), do: school
  defp school_atom(%Spell{} = spell), do: Enum.at(@schools, Spell.school_index(spell), :physical)
  defp school_atom(_spell), do: :physical

  defp leech_heal_events(%Holder{caster_guid: caster_guid}, %{object: %{guid: owner_guid}}, damage, %Aura{} = aura)
       when is_integer(caster_guid) and caster_guid != owner_guid and damage > 0 do
    multiplier = if is_number(aura.multiple_value) and aura.multiple_value > 0, do: aura.multiple_value, else: 1.0
    [Event.heal_entity(caster_guid, trunc(damage * multiplier))]
  end

  defp leech_heal_events(_holder, _entity, _damage, _aura), do: []

  defp apply_energize(entity, %Holder{} = holder, 0, amount) do
    entity = Core.restore_mana(entity, amount)

    event =
      Event.periodic_aura_log(holder.caster_guid, entity.object.guid, holder.spell, :periodic_energize, amount,
        misc_value: 0
      )

    {entity, [event]}
  end

  defp apply_energize(entity, %Holder{} = holder, power_type, amount) when is_integer(power_type) and power_type > 0 do
    entity = Resources.gain_power(entity, power_type, amount)

    event =
      Event.periodic_aura_log(holder.caster_guid, entity.object.guid, holder.spell, :periodic_energize, amount,
        misc_value: power_type
      )

    {entity, [event]}
  end

  defp apply_energize(entity, _holder, _power_type, _amount), do: {entity, []}

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
