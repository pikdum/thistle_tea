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
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Dispel
  alias ThistleTea.Game.Entity.Logic.Aura.Heartbeat
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.PersistentArea

  @aura_interrupt_damage 0x02
  @aura_interrupt_cast 0x01
  @aura_interrupt_move 0x08
  @aura_interrupt_turning 0x10
  @aura_interrupt_not_seated 0x40000
  @aura_interrupt_above_water 0x100
  @aura_interrupt_under_water 0x80

  def interrupt_mask(:move), do: @aura_interrupt_move ||| @aura_interrupt_turning ||| @aura_interrupt_not_seated
  def interrupt_mask(:cast), do: @aura_interrupt_cast
  def interrupt_mask(:turn), do: @aura_interrupt_turning
  def interrupt_mask(:stand), do: @aura_interrupt_not_seated
  def interrupt_mask(:above_water), do: @aura_interrupt_above_water
  def interrupt_mask(:under_water), do: @aura_interrupt_under_water
  def interrupt_mask(:action), do: 0x00000004
  def interrupt_mask(:action_complete), do: 0x00010000
  def interrupt_mask(:attack), do: 0x00001000

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

  def remove_on_evade(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) do
    {kept, removed} = Enum.split_with(holders, &keep_on_evade?(&1, entity))
    if removed == [], do: {entity, []}, else: transition(entity, kept, :removed, now)
  end

  def remove_on_evade(entity, _now), do: {entity, []}

  defp keep_on_evade?(holder, %{internal: %Internal{creature: %Creature{extra_flags: flags}}})
       when is_integer(flags) and Bitwise.band(flags, 0x00001000) != 0, do: not holder.negative?

  defp keep_on_evade?(holder, _entity) do
    Spell.custom?(holder.spell, :not_removed_on_evade) or
      (not holder.negative? and is_integer(holder.expires_at) and holder.expires_at >= 0 and
         Guid.entity_type(holder.caster_guid) == :player)
  end

  def remove_with_interrupt_flags(entity, mask, now, preserved_types \\ [])

  def remove_with_interrupt_flags(%{unit: %Unit{auras: holders}} = entity, mask, now, preserved_types)
      when is_list(holders) and holders != [] and is_integer(mask) do
    {removed, kept} =
      Enum.split_with(holders, &(Holder.interruptible?(&1, mask) and not Holder.has_any_type?(&1, preserved_types)))

    if removed == [] do
      {entity, []}
    else
      transition(entity, kept, :interrupted, now)
    end
  end

  def remove_with_interrupt_flags(entity, _mask, _now, _preserved_types), do: {entity, []}

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

  def remove_area_aura(%{unit: %Unit{auras: holders}} = entity, area_guid, now) do
    kept =
      Enum.reject(holders || [], fn
        %Holder{cast_context: %CastContext{persistent_area: %PersistentArea{guid: ^area_guid}}} -> true
        _holder -> false
      end)

    transition(entity, kept, :removed, now)
  end

  def delay_source_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, caster_guid, delay_ms, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) and is_integer(caster_guid) and
             is_integer(delay_ms) and delay_ms > 0 do
    {holders, events} =
      Enum.map_reduce(holders, [], fn %Holder{} = holder, events ->
        if Holder.same_source?(holder, spell_id, caster_guid) and is_integer(holder.expires_at) do
          holder = %{holder | expires_at: max(holder.expires_at - delay_ms, now)}
          holder = Heartbeat.delay(holder, delay_ms, now)
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

  def dispel(entity, dispel_type, now, polarity \\ nil, count \\ 1) do
    {entity, events, _spell_ids} = Dispel.apply(entity, dispel_type, now, polarity, count)
    {entity, events}
  end

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

  def duration_event(%Holder{slot: slot, expires_at: expires_at}, now)
      when is_integer(slot) and is_integer(expires_at) and expires_at != -1 do
    [Effects.aura_duration(slot, max(expires_at - now, 0))]
  end

  def duration_event(_holder, _now), do: []
end
