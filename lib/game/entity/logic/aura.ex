defmodule ThistleTea.Game.Entity.Logic.Aura do
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2, bnot: 1]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  require Logger

  @movement_flag_root 0x08000000

  @max_slots 48
  @max_positive_slots 32

  @aflag_cancelable 0x01
  @aflag_eff_index_2 0x02
  @aflag_eff_index_1 0x04
  @aflag_eff_index_0 0x08

  @negative_auras [:periodic_damage, :mod_root, :mod_decrease_speed, :mod_stun, :mod_fear]

  def apply_spell(entity, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    aura_effects = Spell.aura_effects(spell)

    case build_auras(aura_effects, now) do
      [] ->
        {entity, []}

      auras ->
        target_guid = entity.object.guid

        holder = %Holder{
          spell: spell,
          caster_guid: context.caster_guid,
          caster_level: context.caster_level,
          applied_at: now,
          expires_at: expires_at(now, spell.duration_ms),
          auras: auras,
          negative?: negative?(auras, context.caster_guid, target_guid)
        }

        do_apply(entity, holder, now)
    end
  end

  def apply_spell(entity, caster_guid, caster_level, %Spell{} = spell, now) when is_integer(now) do
    context = %CastContext{
      caster_guid: caster_guid,
      caster_level: caster_level,
      target_guid: entity.object.guid,
      spell: spell
    }

    apply_spell(entity, context, spell, now)
  end

  defp negative?(auras, caster_guid, target_guid) do
    cond do
      caster_guid == target_guid -> false
      Enum.any?(auras, fn %Aura{type: type} -> type in @negative_auras end) -> true
      true -> false
    end
  end

  defp do_apply(%{unit: %Unit{auras: existing}} = entity, %Holder{} = holder, now) when is_list(existing) do
    holders = upsert_holder(existing, holder)
    unit = sync_unit(%{entity.unit | auras: holders})

    {entity, events} =
      entity
      |> Map.put(:unit, unit)
      |> sync_movement_state(now)

    {Core.mark_broadcast_update(entity), events}
  end

  defp do_apply(entity, %Holder{} = holder, now) do
    do_apply(%{entity | unit: %{entity.unit | auras: []}}, holder, now)
  end

  defp upsert_holder(existing, %Holder{spell: %Spell{id: spell_id}, caster_guid: caster_guid} = incoming) do
    case Enum.find_index(existing, &same_source?(&1, spell_id, caster_guid)) do
      nil ->
        slot = next_free_slot(existing, incoming.negative?)
        existing ++ [%{incoming | slot: slot}]

      index ->
        old = Enum.at(existing, index)
        refreshed = %{incoming | slot: old.slot}
        List.replace_at(existing, index, refreshed)
    end
  end

  defp same_source?(%Holder{spell: %Spell{id: id}, caster_guid: caster}, spell_id, caster_guid) do
    id == spell_id and caster == caster_guid
  end

  defp same_source?(_holder, _spell_id, _caster_guid), do: false

  def self_duration_events(%ThistleTea.Character{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.flat_map(holders, &duration_event/1)
  end

  def self_duration_events(_entity), do: []

  def reactions(%{object: %{guid: owner_guid}, unit: %Unit{auras: holders}}, :hit_taken, %{attacker_guid: attacker_guid})
      when is_list(holders) and is_integer(attacker_guid) do
    holders
    |> Enum.flat_map(fn %Holder{} = holder ->
      Enum.flat_map(holder.auras, &reaction_event(&1, holder, owner_guid, attacker_guid))
    end)
  end

  def reactions(_entity, _event, _context), do: []

  def expire_due(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) do
    {kept, expired} = Enum.split_with(holders, &alive?(&1, now))

    if expired == [] do
      {entity, []}
    else
      unit = sync_unit(%{entity.unit | auras: kept})

      {entity, events} =
        entity
        |> Map.put(:unit, unit)
        |> sync_movement_state(now)

      {Core.mark_broadcast_update(entity), events}
    end
  end

  def expire_due(entity, _now), do: {entity, []}

  def rooted?(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.any?(holders, &has_aura_type?(&1, :mod_root))
  end

  def rooted?(_entity), do: false

  defp has_aura_type?(%Holder{auras: auras}, type) do
    Enum.any?(auras, fn %Aura{type: t} -> t == type end)
  end

  defp sync_movement_flags(%{movement_block: %MovementBlock{} = mb, unit: %Unit{auras: holders}} = entity, now) do
    flags = mb.movement_flags || 0
    was_rooted? = (flags &&& @movement_flag_root) != 0
    has_root? = Enum.any?(holders, &has_aura_type?(&1, :mod_root))

    new_flags =
      if has_root?,
        do: flags ||| @movement_flag_root,
        else: flags &&& bnot(@movement_flag_root)

    entity = %{entity | movement_block: %{mb | movement_flags: new_flags}}
    root_events = if has_root? == was_rooted?, do: [], else: [Event.movement_root_changed(has_root?)]

    if has_root? and not was_rooted? do
      {Movement.halt(entity, now), [Event.movement_stopped() | root_events]}
    else
      {entity, root_events}
    end
  end

  defp sync_movement_flags(entity, _now), do: {entity, []}

  defp sync_movement_state(entity, now) do
    old_run_speed = run_speed(entity)
    entity = MovementStats.sync_aura_mods(entity)
    {entity, events} = sync_movement_flags(entity, now)
    {entity, speed_change_events(entity, old_run_speed) ++ events}
  end

  defp speed_change_events(entity, old_run_speed) do
    new_run_speed = run_speed(entity)

    if is_number(old_run_speed) and is_number(new_run_speed) and old_run_speed != new_run_speed do
      [Event.movement_speed_changed(new_run_speed)]
    else
      []
    end
  end

  defp run_speed(%{movement_block: %MovementBlock{run_speed: run_speed}}), do: run_speed
  defp run_speed(_entity), do: nil

  def tick(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    entity
    |> tick_periodics(now)
    |> then(fn {entity, events} ->
      {entity, expire_events} = expire_due(entity, now)
      {entity, events ++ expire_events}
    end)
  end

  def tick(entity, _now), do: {entity, []}

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
        new_holders = Enum.reverse(acc)

        entity =
          if new_holders == holders do
            entity
          else
            %{entity | unit: %{entity.unit | auras: new_holders}}
          end

        {entity, events}
    end
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
    entity = Core.take_damage(entity, damage, now)

    event =
      Event.spell_damage(holder.caster_guid, entity.object.guid, holder.spell, damage, periodic?: true)

    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, [event]}
  end

  defp tick_aura(entity, _holder, aura, _now), do: {entity, aura, []}

  defp advance_tick(last_tick, amplitude_ms, now) when is_integer(amplitude_ms) and amplitude_ms > 0 do
    next = last_tick + amplitude_ms
    if next > now, do: next, else: advance_tick(next, amplitude_ms, now)
  end

  defp advance_tick(_last_tick, _amplitude_ms, now), do: now + 1_000

  defp duration_event(%Holder{slot: slot, applied_at: applied_at, expires_at: expires_at})
       when is_integer(slot) and is_integer(applied_at) and is_integer(expires_at) do
    [Event.aura_duration(slot, max(expires_at - applied_at, 0))]
  end

  defp duration_event(_holder), do: []

  def next_event_at(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.flat_map(&holder_event_times/1)
    |> Enum.min(fn -> nil end)
  end

  def next_event_at(_entity), do: nil

  defp holder_event_times(%Holder{} = holder) do
    tick_times = Enum.flat_map(holder.auras, &aura_tick_time/1)
    if is_integer(holder.expires_at), do: [holder.expires_at | tick_times], else: tick_times
  end

  defp aura_tick_time(%Aura{next_tick_at: at}) when is_integer(at), do: [at]
  defp aura_tick_time(_), do: []

  defp alive?(%Holder{expires_at: nil}, _now), do: true
  defp alive?(%Holder{expires_at: -1}, _now), do: true
  defp alive?(%Holder{expires_at: expires_at}, now) when is_integer(expires_at), do: now < expires_at
  defp alive?(_holder, _now), do: true

  defp expires_at(_now, 0), do: nil
  defp expires_at(_now, nil), do: nil
  defp expires_at(_now, -1), do: -1
  defp expires_at(now, duration_ms) when is_integer(duration_ms), do: now + duration_ms

  defp build_auras(effects, now) do
    Enum.reduce(effects, [], fn effect, acc ->
      case build_aura(effect, now) do
        nil -> acc
        aura -> [aura | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp build_aura(%Effect{aura: nil}, _now), do: nil

  defp build_aura(%Effect{} = effect, now) do
    %Aura{
      index: effect.index,
      type: effect.aura,
      amount: Effect.damage_roll(effect),
      misc_value: effect.misc_value,
      amplitude_ms: effect.amplitude_ms,
      next_tick_at: next_tick(effect, now),
      trigger_spell_id: effect.trigger_spell_id
    }
  end

  defp reaction_event(%Aura{type: type, trigger_spell_id: spell_id}, %Holder{} = holder, owner_guid, attacker_guid)
       when type in [:damage_shield, :proc_trigger_spell] and is_integer(spell_id) and spell_id > 0 do
    source_guid = holder.caster_guid || owner_guid
    source_level = holder.caster_level || 1
    [Event.trigger_spell(source_guid, source_level, attacker_guid, spell_id)]
  end

  defp reaction_event(_aura, _holder, _owner_guid, _attacker_guid), do: []

  defp next_tick(%Effect{aura: aura, amplitude_ms: amp}, now)
       when aura in [:periodic_damage, :periodic_heal] and is_integer(amp) and amp > 0 do
    now + amp
  end

  defp next_tick(_effect, _now), do: nil

  defp next_free_slot(holders, negative?) do
    used = MapSet.new(holders, & &1.slot)
    range = if negative?, do: @max_positive_slots..(@max_slots - 1), else: 0..(@max_positive_slots - 1)
    Enum.find(range, &(not MapSet.member?(used, &1)))
  end

  def sync_unit(%Unit{} = unit) do
    unit
    |> Stats.sync_aura_mods()
    |> sync_aura_fields()
  end

  defp sync_aura_fields(%Unit{auras: holders} = unit) when is_list(holders) and holders != [] do
    %{
      unit
      | aura: pack_aura_ids(holders),
        aura_flags: pack_aura_flags(holders),
        aura_levels: pack_aura_levels(holders),
        aura_applications: pack_aura_applications(holders)
    }
  end

  defp sync_aura_fields(%Unit{} = unit) do
    %{
      unit
      | aura: 0,
        aura_flags: <<0::size(@max_slots * 4)>>,
        aura_levels: <<0::size(@max_slots * 8)>>,
        aura_applications: <<0::size(@max_slots * 8)>>
    }
  end

  defp pack_aura_ids(holders) do
    Enum.reduce(holders, 0, fn %Holder{slot: slot, spell: %Spell{id: id}}, acc ->
      acc ||| id <<< (32 * slot)
    end)
  end

  defp pack_aura_flags(holders) do
    int =
      Enum.reduce(holders, 0, fn %Holder{} = holder, acc ->
        acc ||| holder_flag_bits(holder) <<< (4 * holder.slot)
      end)

    <<int::little-size(24 * 8)>>
  end

  defp holder_flag_bits(%Holder{auras: auras, negative?: negative?}) do
    base = if negative?, do: 0, else: @aflag_cancelable

    Enum.reduce(auras, base, fn %Aura{index: index}, acc ->
      acc ||| aura_index_bit(index)
    end)
  end

  defp aura_index_bit(0), do: @aflag_eff_index_0
  defp aura_index_bit(1), do: @aflag_eff_index_1
  defp aura_index_bit(2), do: @aflag_eff_index_2
  defp aura_index_bit(_), do: 0

  defp pack_aura_levels(holders) do
    for slot <- 0..(@max_slots - 1), into: <<>> do
      level = level_for_slot(holders, slot)
      <<level::8>>
    end
  end

  defp pack_aura_applications(holders) do
    for slot <- 0..(@max_slots - 1), into: <<>> do
      apps = if Enum.any?(holders, &(&1.slot == slot)), do: 0, else: 0
      <<apps::8>>
    end
  end

  defp level_for_slot(holders, slot) do
    case Enum.find(holders, &(&1.slot == slot)) do
      %Holder{caster_level: level} when is_integer(level) -> level
      _ -> 0
    end
  end
end
