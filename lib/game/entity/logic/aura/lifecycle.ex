defmodule ThistleTea.Game.Entity.Logic.Aura.Lifecycle do
  @moduledoc """
  Removes auras from an entity for every reason they can end — expired
  duration, interrupt flags (moving, turning, standing), explicit removal or
  player cancel, dispel, and breaking on damage — then resyncs the unit and
  movement state.
  """
  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @aura_interrupt_damage 0x02
  @aura_interrupt_cast 0x01
  @aura_interrupt_move 0x08
  @aura_interrupt_turning 0x10
  @aura_interrupt_not_seated 0x40000
  @aura_interrupt_above_water 0x100

  def interrupt_mask(:move), do: @aura_interrupt_move ||| @aura_interrupt_turning ||| @aura_interrupt_not_seated
  def interrupt_mask(:cast), do: @aura_interrupt_cast
  def interrupt_mask(:turn), do: @aura_interrupt_turning
  def interrupt_mask(:stand), do: @aura_interrupt_not_seated
  def interrupt_mask(:above_water), do: @aura_interrupt_above_water

  def self_duration_events(%Character{unit: %Unit{auras: holders}}, now) when is_list(holders) and is_integer(now) do
    Enum.flat_map(holders, &duration_event(&1, now))
  end

  def self_duration_events(_entity, _now), do: []

  def expire_due(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) do
    {kept, expired} = Enum.split_with(holders, &Holder.alive?(&1, now))

    if expired == [] do
      {entity, []}
    else
      transition(entity, kept, :expired, now)
    end
  end

  def expire_due(entity, _now), do: {entity, []}

  def remove_with_interrupt_flags(%{unit: %Unit{auras: holders}} = entity, mask, now)
      when is_list(holders) and holders != [] and is_integer(mask) do
    {removed, kept} = Enum.split_with(holders, &Holder.interruptible?(&1, mask))

    if removed == [] do
      {entity, []}
    else
      transition(entity, kept, :interrupted, now)
    end
  end

  def remove_with_interrupt_flags(entity, _mask, _now), do: {entity, []}

  def remove_spells(%{unit: %Unit{auras: holders}} = entity, spell_ids, now)
      when is_list(holders) and holders != [] and is_list(spell_ids) do
    {removed, kept} = Enum.split_with(holders, fn %Holder{spell: %Spell{id: id}} -> id in spell_ids end)

    if removed == [] do
      {entity, []}
    else
      transition(entity, kept, :removed, now)
    end
  end

  def remove_spells(entity, _spell_ids, _now), do: {entity, []}

  def spend_spell_charges(%{unit: %Unit{auras: holders}} = entity, spell_ids, now)
      when is_list(holders) and holders != [] and is_list(spell_ids) do
    {holders, _removed} =
      Enum.map_reduce(holders, [], &spend_holder_charge(&1, spell_ids, &2))

    holders = Enum.reject(holders, &is_nil/1)

    if holders == entity.unit.auras do
      {entity, []}
    else
      transition(entity, holders, :consumed, now)
    end
  end

  def spend_spell_charges(entity, _spell_ids, _now), do: {entity, []}

  defp spend_holder_charge(%Holder{spell: %Spell{id: id}} = holder, spell_ids, removed) do
    if id in spell_ids, do: spend_holder_charge(holder, removed), else: {holder, removed}
  end

  defp spend_holder_charge(holder, _spell_ids, removed), do: {holder, removed}

  defp spend_holder_charge(%Holder{charges: charges} = holder, removed) when is_integer(charges) and charges > 1 do
    {%{holder | charges: charges - 1}, removed}
  end

  defp spend_holder_charge(%Holder{charges: charges} = holder, removed) when is_integer(charges) do
    {nil, [holder | removed]}
  end

  defp spend_holder_charge(holder, removed), do: {holder, removed}

  def remove_aura_types(%{unit: %Unit{auras: holders}} = entity, aura_types, now)
      when is_list(holders) and holders != [] and is_list(aura_types) do
    {removed, kept} =
      Enum.split_with(holders, fn holder -> Enum.any?(aura_types, &Holder.has_aura_type?(holder, &1)) end)

    if removed == [], do: {entity, []}, else: transition(entity, kept, :removed, now)
  end

  def remove_aura_types(entity, _aura_types, _now), do: {entity, []}

  def remove_source_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, caster_guid, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) and is_integer(caster_guid) do
    {removed, kept} =
      Enum.split_with(holders, fn %Holder{spell: %Spell{id: id}, caster_guid: source_guid} ->
        id == spell_id and source_guid == caster_guid
      end)

    if removed == [], do: {entity, []}, else: transition(entity, kept, :removed, now)
  end

  def remove_source_spell(entity, _spell_id, _caster_guid, _now), do: {entity, []}

  def delay_source_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, caster_guid, delay_ms, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) and is_integer(caster_guid) and
             is_integer(delay_ms) and delay_ms > 0 do
    {holders, events} =
      Enum.map_reduce(holders, [], fn %Holder{} = holder, events ->
        if Holder.same_source?(holder, spell_id, caster_guid) and is_integer(holder.expires_at) do
          holder = %{holder | expires_at: max(holder.expires_at - delay_ms, now)}
          {holder, events ++ duration_event(holder, now)}
        else
          {holder, events}
        end
      end)

    {entity, transition_events} = transition(entity, holders, :delayed, now)
    Effects.enqueue(entity, transition_events ++ duration_sync_events(entity, events))
  end

  def delay_source_spell(entity, _spell_id, _caster_guid, _delay_ms, _now), do: entity

  defp duration_sync_events(%Character{}, events), do: events
  defp duration_sync_events(_entity, _events), do: []

  def cancel_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) do
    holder = Enum.find(holders, fn %Holder{spell: %Spell{id: id}} -> id == spell_id end)

    if cancelable?(holder) do
      spell_ids =
        if stealth_holder?(holder),
          do: stealth_spell_ids(holders),
          else: [spell_id | Script.cancel_linked_spell_ids(holder)]

      kept =
        Enum.reject(holders, fn %Holder{spell: %Spell{id: id}} ->
          id in spell_ids
        end)

      transition(entity, kept, :cancelled, now)
    else
      {entity, []}
    end
  end

  def cancel_spell(entity, _spell_id, _now), do: {entity, []}

  def dispel(entity, dispel_type, now, polarity \\ nil, count \\ 1)

  def dispel(%{unit: %Unit{auras: holders}} = entity, dispel_type, now, polarity, count)
      when is_list(holders) and holders != [] and is_integer(dispel_type) and is_integer(count) and count > 0 do
    holders
    |> dispel_indexes(dispel_type, polarity)
    |> Enum.take_random(count)
    |> case do
      [] ->
        {entity, []}

      indexes ->
        kept =
          holders
          |> Enum.with_index()
          |> Enum.reject(fn {_holder, index} -> index in indexes end)
          |> Enum.map(&elem(&1, 0))

        transition(entity, kept, :dispelled, now)
    end
  end

  def dispel(entity, _dispel_type, _now, _polarity, _count), do: {entity, []}

  def break_on_damage(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    {removed, kept} =
      Enum.split_with(holders, fn holder ->
        Holder.has_aura_type?(holder, :mod_confuse) or Holder.interruptible?(holder, @aura_interrupt_damage)
      end)

    if removed == [] do
      entity
    else
      {entity, events} = transition(entity, kept, :interrupted, now)
      Effects.enqueue(entity, events)
    end
  end

  def break_on_damage(entity, _now), do: entity

  defp transition(entity, holders, cause, now) do
    Transition.run(entity, %Change{holders: holders, cause: cause, now: now})
  end

  defp cancelable?(%Holder{negative?: true}), do: false

  defp cancelable?(%Holder{spell: %Spell{} = spell}) do
    not Spell.attribute?(spell, :passive) and not Spell.attribute?(spell, :cant_cancel)
  end

  defp cancelable?(_holder), do: false

  defp stealth_holder?(%Holder{} = holder) do
    Holder.has_aura_type?(holder, :mod_stealth) or
      Enum.any?(holder.auras, &match?(%Aura{type: :mod_shapeshift, misc_value: 30}, &1))
  end

  defp stealth_spell_ids(holders) do
    for %Holder{spell: %Spell{id: id}} = holder <- holders, stealth_holder?(holder), do: id
  end

  defp dispel_indexes(holders, dispel_type, polarity) do
    matches_type? = fn %Holder{spell: %Spell{dispel_type: dt}} -> dt == dispel_type end

    matcher =
      case polarity do
        :negative -> &(matches_type?.(&1) and &1.negative?)
        :positive -> &(matches_type?.(&1) and not &1.negative?)
        _ -> matches_type?
      end

    for {holder, index} <- Enum.with_index(holders), matcher.(holder), do: index
  end

  def duration_event(%Holder{slot: slot, expires_at: expires_at}, now)
      when is_integer(slot) and is_integer(expires_at) and expires_at != -1 do
    [Effects.aura_duration(slot, max(expires_at - now, 0))]
  end

  def duration_event(_holder, _now), do: []
end
