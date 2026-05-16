defmodule ThistleTea.Game.Entity.Logic.Aura do
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World

  require Logger

  @max_slots 48
  @max_positive_slots 32

  @aflag_cancelable 0x01
  @aflag_eff_index_2 0x02
  @aflag_eff_index_1 0x04
  @aflag_eff_index_0 0x08

  @negative_auras [:periodic_damage, :mod_root, :mod_decrease_speed, :mod_stun, :mod_fear]

  def apply_spell(entity, caster_guid, caster_level, %Spell{} = spell) do
    aura_effects = Spell.aura_effects(spell)

    case build_auras(aura_effects) do
      [] ->
        entity

      auras ->
        now = Time.now()
        target_guid = entity.object.guid

        holder = %Holder{
          spell: spell,
          caster_guid: caster_guid,
          caster_level: caster_level,
          applied_at: now,
          expires_at: expires_at(now, spell.duration_ms),
          auras: auras,
          negative?: negative?(auras, caster_guid, target_guid)
        }

        do_apply(entity, holder)
    end
  end

  defp negative?(auras, caster_guid, target_guid) do
    cond do
      caster_guid == target_guid -> false
      Enum.any?(auras, fn %Aura{type: type} -> type in @negative_auras end) -> true
      true -> false
    end
  end

  defp do_apply(%{unit: %Unit{auras: existing}} = entity, %Holder{} = holder) when is_list(existing) do
    holders = upsert_holder(existing, holder)
    unit = sync_unit(%{entity.unit | auras: holders})

    entity
    |> Map.put(:unit, unit)
    |> Core.mark_broadcast_update()
  end

  defp do_apply(entity, %Holder{} = holder) do
    do_apply(%{entity | unit: %{entity.unit | auras: []}}, holder)
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

  def notify_self_durations(%ThistleTea.Character{unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    Enum.each(holders, &send_duration_update/1)
    entity
  end

  def notify_self_durations(entity), do: entity

  def expire_due(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) do
    {kept, expired} = Enum.split_with(holders, &alive?(&1, now))

    if expired == [] do
      entity
    else
      unit = sync_unit(%{entity.unit | auras: kept})

      entity
      |> Map.put(:unit, unit)
      |> Core.mark_broadcast_update()
    end
  end

  def expire_due(entity, _now), do: entity

  def tick(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    entity
    |> tick_periodics(now)
    |> expire_due(now)
  end

  def tick(entity, _now), do: entity

  defp tick_periodics(%{unit: %Unit{auras: holders}} = entity, now) do
    result =
      Enum.reduce_while(holders, {entity, []}, fn holder, {ent, acc} ->
        {ent, new_holder} = tick_holder(ent, holder, now)

        if Core.dead?(ent) do
          {:halt, {ent, :died}}
        else
          {:cont, {ent, [new_holder | acc]}}
        end
      end)

    case result do
      {entity, :died} ->
        entity

      {entity, acc} ->
        new_holders = Enum.reverse(acc)

        if new_holders == holders do
          entity
        else
          %{entity | unit: %{entity.unit | auras: new_holders}}
        end
    end
  end

  defp tick_holder(entity, %Holder{auras: auras} = holder, now) do
    {entity, new_auras} =
      Enum.reduce(auras, {entity, []}, fn aura, {ent, acc} ->
        {ent, new_aura} = tick_aura(ent, holder, aura, now)
        {ent, [new_aura | acc]}
      end)

    {entity, %{holder | auras: Enum.reverse(new_auras)}}
  end

  defp tick_aura(entity, %Holder{} = holder, %Aura{type: :periodic_damage, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    damage = aura.amount
    entity = entity |> Core.take_damage(damage) |> broadcast_periodic_damage(holder, damage)
    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}}
  end

  defp tick_aura(entity, _holder, aura, _now), do: {entity, aura}

  defp advance_tick(last_tick, amplitude_ms, now) when is_integer(amplitude_ms) and amplitude_ms > 0 do
    next = last_tick + amplitude_ms
    if next > now, do: next, else: advance_tick(next, amplitude_ms, now)
  end

  defp advance_tick(_last_tick, _amplitude_ms, now), do: now + 1_000

  defp broadcast_periodic_damage(entity, %Holder{} = holder, damage) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: holder.caster_guid || 0,
      target: entity.object.guid,
      spell_id: holder.spell.id,
      damage: damage,
      school: school_index(holder.spell.school),
      periodic?: true
    }
    |> World.broadcast_packet(entity)

    entity
  end

  defp send_duration_update(%Holder{slot: slot, applied_at: applied_at, expires_at: expires_at})
       when is_integer(slot) and is_integer(applied_at) and is_integer(expires_at) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: slot,
      duration_ms: max(expires_at - applied_at, 0)
    })
  end

  defp send_duration_update(_holder), do: :ok

  defp school_index(:physical), do: 0
  defp school_index(:holy), do: 1
  defp school_index(:fire), do: 2
  defp school_index(:nature), do: 3
  defp school_index(:frost), do: 4
  defp school_index(:shadow), do: 5
  defp school_index(:arcane), do: 6
  defp school_index(other) when is_integer(other), do: other
  defp school_index(_), do: 0

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

  defp build_auras(effects) do
    now = Time.now()

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
      next_tick_at: next_tick(effect, now)
    }
  end

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
    |> reset_resistances()
    |> apply_resistance_mods()
    |> sync_aura_fields()
  end

  defp reset_resistances(%Unit{} = unit) do
    %{
      unit
      | normal_resistance: 0,
        holy_resistance: 0,
        fire_resistance: 0,
        nature_resistance: 0,
        frost_resistance: 0,
        shadow_resistance: 0,
        arcane_resistance: 0
    }
  end

  defp apply_resistance_mods(%Unit{auras: holders} = unit) when is_list(holders) do
    Enum.reduce(holders, unit, fn %Holder{auras: auras}, u ->
      Enum.reduce(auras, u, &apply_aura_mod/2)
    end)
  end

  defp apply_resistance_mods(unit), do: unit

  defp apply_aura_mod(%Aura{type: :mod_resistance, amount: amount, misc_value: mask}, %Unit{} = unit)
       when is_integer(amount) do
    Enum.reduce(school_fields_for_mask(mask), unit, fn field, u ->
      Map.update!(u, field, &(&1 + amount))
    end)
  end

  defp apply_aura_mod(_aura, unit), do: unit

  defp school_fields_for_mask(mask) when is_integer(mask) do
    [
      {0x01, :normal_resistance},
      {0x02, :holy_resistance},
      {0x04, :fire_resistance},
      {0x08, :nature_resistance},
      {0x10, :frost_resistance},
      {0x20, :shadow_resistance},
      {0x40, :arcane_resistance}
    ]
    |> Enum.filter(fn {bit, _} -> (mask &&& bit) != 0 end)
    |> Enum.map(fn {_, field} -> field end)
  end

  defp school_fields_for_mask(_), do: []

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
