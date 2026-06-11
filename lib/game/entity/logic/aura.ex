defmodule ThistleTea.Game.Entity.Logic.Aura do
  @moduledoc """
  Pure aura lifecycle logic: applying a cast spell's auras to an entity with
  rank, same-source, and exclusive-category stacking rules, expiring auras whose
  duration has elapsed, and deriving interrupt/reaction events (e.g. breaking
  fear on hit, cancelling seated auras on move).
  """
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
  @movement_flag_safe_fall 0x20000000
  @movement_flag_water_walk 0x10000000
  @movement_flag_hover 0x40000000

  @unit_flag_stunned 0x00040000

  @max_slots 48
  @max_positive_slots 32

  @aflag_cancelable 0x01
  @aflag_eff_index_2 0x02
  @aflag_eff_index_1 0x04
  @aflag_eff_index_0 0x08

  @negative_auras [
    :periodic_damage,
    :periodic_leech,
    :mod_root,
    :mod_decrease_speed,
    :mod_stun,
    :mod_fear,
    :mod_confuse,
    :mod_possess,
    :mod_detect_range
  ]

  @aura_interrupt_damage 0x02
  @aura_interrupt_move 0x08
  @aura_interrupt_turning 0x10
  @aura_interrupt_not_seated 0x40000

  @regen_tick_ms 5000
  @percent_regen_tick_ms 2000
  @regen_auras [:mod_regen, :mod_power_regen, :mod_power_regen_percent]

  @stand_state_sit 1

  def interrupt_mask(:move), do: @aura_interrupt_move ||| @aura_interrupt_turning ||| @aura_interrupt_not_seated
  def interrupt_mask(:turn), do: @aura_interrupt_turning
  def interrupt_mask(:stand), do: @aura_interrupt_not_seated

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
          charges: holder_charges(spell),
          auras: auras,
          negative?: negative?(spell, auras, context.caster_guid, target_guid)
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

  defp negative?(spell, auras, caster_guid, target_guid) do
    cond do
      Spell.attribute?(spell, :negative) -> true
      caster_guid == target_guid -> false
      Enum.any?(auras, fn %Aura{type: type} -> type in @negative_auras end) -> true
      true -> false
    end
  end

  defp do_apply(%{unit: %Unit{auras: existing}} = entity, %Holder{} = holder, now) when is_list(existing) do
    cond do
      blocked_by_stronger_rank?(existing, holder.spell) ->
        {entity, []}

      blocked_by_mechanic_immunity?(existing, holder.spell) ->
        {consume_immunity_charge(entity, holder.spell), []}

      true ->
        do_apply_unblocked(entity, existing, holder, now)
    end
  end

  defp do_apply(entity, %Holder{} = holder, now) do
    do_apply(%{entity | unit: %{entity.unit | auras: []}}, holder, now)
  end

  defp do_apply_unblocked(entity, existing, %Holder{} = holder, now) do
    existing =
      existing
      |> remove_immune_mechanics(holder)
      |> remove_non_stacking(holder)

    holders = upsert_holder(existing, holder)
    unit = sync_unit(%{entity.unit | auras: holders})

    {entity, sit_events} =
      entity
      |> Map.put(:unit, unit)
      |> maybe_sit(holder)

    {entity, events} = sync_movement_state(entity, now)

    {Core.mark_broadcast_update(entity), sit_events ++ events}
  end

  def blocked_by_stronger_rank?(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    blocked_by_stronger_rank?(holders, spell)
  end

  def blocked_by_stronger_rank?(holders, %Spell{} = spell) when is_list(holders) do
    Enum.any?(holders, fn %Holder{spell: other} -> Spell.stronger_rank_of_same_chain?(other, spell) end)
  end

  def blocked_by_stronger_rank?(_entity, _spell), do: false

  defp remove_non_stacking(holders, %Holder{spell: %Spell{} = spell, caster_guid: caster_guid}) do
    Enum.reject(holders, fn %Holder{spell: %Spell{} = other} = existing ->
      Spell.same_chain?(other, spell) or
        Spell.same_exclusive_category?(other, spell) or
        (other.id == spell.id and existing.caster_guid != caster_guid)
    end)
  end

  defp holder_charges(%Spell{proc_charges: charges}) when is_integer(charges) and charges > 0, do: charges
  defp holder_charges(_spell), do: nil

  def mechanic_immune?(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    blocked_by_mechanic_immunity?(holders, spell)
  end

  def mechanic_immune?(_entity, _spell), do: false

  defp blocked_by_mechanic_immunity?(holders, %Spell{mechanic: mechanic}) when is_integer(mechanic) and mechanic > 0 do
    Enum.any?(holders, &immunity_holder_for_mechanic?(&1, mechanic))
  end

  defp blocked_by_mechanic_immunity?(_holders, _spell), do: false

  defp immunity_holder_for_mechanic?(%Holder{auras: auras}, mechanic) do
    Enum.any?(auras, &match?(%Aura{type: :mechanic_immunity, misc_value: ^mechanic}, &1))
  end

  defp consume_immunity_charge(%{unit: %Unit{auras: holders}} = entity, %Spell{mechanic: mechanic}) do
    case Enum.find_index(holders, &(&1.charges != nil and immunity_holder_for_mechanic?(&1, mechanic))) do
      nil ->
        entity

      index ->
        holders = spend_holder_charge(holders, index)

        %{entity | unit: sync_unit(%{entity.unit | auras: holders})}
        |> Core.mark_broadcast_update()
    end
  end

  defp spend_holder_charge(holders, index) do
    case Enum.at(holders, index) do
      %Holder{charges: charges} when is_integer(charges) and charges > 1 ->
        List.update_at(holders, index, &%{&1 | charges: charges - 1})

      %Holder{charges: charges} when is_integer(charges) ->
        List.delete_at(holders, index)

      _holder ->
        holders
    end
  end

  defp remove_immune_mechanics(holders, %Holder{auras: auras}) do
    immune_types =
      auras
      |> Enum.filter(&match?(%Aura{type: :mechanic_immunity}, &1))
      |> Enum.flat_map(&mechanic_aura_types(&1.misc_value))

    case immune_types do
      [] -> holders
      types -> Enum.reject(holders, &holder_has_any_type?(&1, types))
    end
  end

  defp holder_has_any_type?(%Holder{auras: auras}, types) do
    Enum.any?(auras, fn %Aura{type: type} -> type in types end)
  end

  defp mechanic_aura_types(5), do: [:mod_fear]
  defp mechanic_aura_types(7), do: [:mod_root]
  defp mechanic_aura_types(11), do: [:mod_decrease_speed]
  defp mechanic_aura_types(12), do: [:mod_stun]
  defp mechanic_aura_types(_), do: []

  defp upsert_holder(existing, %Holder{spell: %Spell{id: spell_id}, caster_guid: caster_guid} = incoming) do
    case Enum.find_index(existing, &same_source?(&1, spell_id, caster_guid)) do
      nil ->
        slot = next_free_slot(existing, incoming.negative?)
        existing ++ [%{incoming | slot: slot}]

      index ->
        old = Enum.at(existing, index)
        refreshed = %{incoming | slot: old.slot, auras: carry_tick_times(old.auras, incoming.auras)}
        List.replace_at(existing, index, refreshed)
    end
  end

  defp carry_tick_times(old_auras, new_auras) do
    Enum.map(new_auras, fn %Aura{} = aura ->
      case Enum.find(old_auras, &(&1.index == aura.index and &1.type == aura.type)) do
        %Aura{next_tick_at: at} when is_integer(at) -> %{aura | next_tick_at: at}
        _ -> aura
      end
    end)
  end

  defp same_source?(%Holder{spell: %Spell{id: id}, caster_guid: caster}, spell_id, caster_guid) do
    id == spell_id and caster == caster_guid
  end

  defp same_source?(_holder, _spell_id, _caster_guid), do: false

  def self_duration_events(%ThistleTea.Character{unit: %Unit{auras: holders}}, now)
      when is_list(holders) and is_integer(now) do
    Enum.flat_map(holders, &duration_event(&1, now))
  end

  def self_duration_events(_entity, _now), do: []

  @charge_consuming_on_hit [:damage_shield, :proc_trigger_spell, :mod_resistance, :mod_resistance_exclusive]

  def reactions(%{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity, :hit_taken, %{
        attacker_guid: attacker_guid
      })
      when is_list(holders) and is_integer(attacker_guid) do
    events =
      Enum.flat_map(holders, fn %Holder{} = holder ->
        Enum.flat_map(holder.auras, &reaction_event(&1, holder, owner_guid, attacker_guid))
      end)

    {spend_hit_charges(entity), events}
  end

  def reactions(entity, _event, _context), do: {entity, []}

  defp spend_hit_charges(%{unit: %Unit{auras: holders}} = entity) do
    new_holders =
      holders
      |> Enum.map(&spend_hit_charge/1)
      |> Enum.reject(&is_nil/1)

    if new_holders == holders do
      entity
    else
      %{entity | unit: sync_unit(%{entity.unit | auras: new_holders})}
      |> Core.mark_broadcast_update()
    end
  end

  defp spend_hit_charge(%Holder{charges: charges} = holder) when is_integer(charges) do
    cond do
      not holder_has_any_type?(holder, @charge_consuming_on_hit) -> holder
      charges > 1 -> %{holder | charges: charges - 1}
      true -> nil
    end
  end

  defp spend_hit_charge(holder), do: holder

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

  def remove_with_interrupt_flags(%{unit: %Unit{auras: holders}} = entity, mask, now)
      when is_list(holders) and holders != [] and is_integer(mask) do
    {removed, kept} = Enum.split_with(holders, &interruptible?(&1, mask))

    if removed == [] do
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

  def remove_with_interrupt_flags(entity, _mask, _now), do: {entity, []}

  def remove_spells(%{unit: %Unit{auras: holders}} = entity, spell_ids, now)
      when is_list(holders) and holders != [] and is_list(spell_ids) do
    {removed, kept} = Enum.split_with(holders, fn %Holder{spell: %Spell{id: id}} -> id in spell_ids end)

    if removed == [] do
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

  def remove_spells(entity, _spell_ids, _now), do: {entity, []}

  def cancel_spell(%{unit: %Unit{auras: holders}} = entity, spell_id, now)
      when is_list(holders) and holders != [] and is_integer(spell_id) do
    holder = Enum.find(holders, fn %Holder{spell: %Spell{id: id}} -> id == spell_id end)

    if cancelable?(holder) do
      remove_spells(entity, [spell_id], now)
    else
      {entity, []}
    end
  end

  def cancel_spell(entity, _spell_id, _now), do: {entity, []}

  defp cancelable?(%Holder{negative?: true}), do: false

  defp cancelable?(%Holder{spell: %Spell{} = spell}) do
    not Spell.attribute?(spell, :passive) and not Spell.attribute?(spell, :cant_cancel)
  end

  defp cancelable?(_holder), do: false

  def dispel(entity, dispel_type, now, polarity \\ nil)

  def dispel(%{unit: %Unit{auras: holders}} = entity, dispel_type, now, polarity)
      when is_list(holders) and holders != [] and is_integer(dispel_type) do
    case dispel_index(holders, dispel_type, polarity) do
      nil ->
        {entity, []}

      index ->
        kept = List.delete_at(holders, index)
        unit = sync_unit(%{entity.unit | auras: kept})

        {entity, events} =
          entity
          |> Map.put(:unit, unit)
          |> sync_movement_state(now)

        {Core.mark_broadcast_update(entity), events}
    end
  end

  def dispel(entity, _dispel_type, _now, _polarity), do: {entity, []}

  defp dispel_index(holders, dispel_type, polarity) do
    matches_type? = fn %Holder{spell: %Spell{dispel_type: dt}} -> dt == dispel_type end

    case polarity do
      :negative -> Enum.find_index(holders, &(matches_type?.(&1) and &1.negative?))
      :positive -> Enum.find_index(holders, &(matches_type?.(&1) and not &1.negative?))
      _ -> Enum.find_index(holders, matches_type?)
    end
  end

  defp interruptible?(%Holder{spell: %Spell{aura_interrupt_flags: flags}}, mask) when is_integer(flags) do
    (flags &&& mask) != 0
  end

  defp interruptible?(_holder, _mask), do: false

  defp maybe_sit(%{unit: %Unit{stand_state: stand_state} = unit} = entity, %Holder{spell: %Spell{} = spell}) do
    if (spell.aura_interrupt_flags &&& @aura_interrupt_not_seated) != 0 and stand_state != @stand_state_sit do
      {%{entity | unit: %{unit | stand_state: @stand_state_sit}}, [Event.stand_state(@stand_state_sit)]}
    else
      {entity, []}
    end
  end

  defp maybe_sit(entity, _holder), do: {entity, []}

  @mana_per_absorbed_damage 2
  @absorb_auras [:school_absorb, :mana_shield]

  def absorb_damage(%{unit: %Unit{auras: holders}} = entity, damage, school)
      when is_list(holders) and holders != [] and is_integer(damage) and damage > 0 do
    school_mask = Spell.school_mask(school)

    {entity, remaining, new_holders} =
      Enum.reduce(holders, {entity, damage, []}, fn holder, {ent, dmg, acc} ->
        {ent, dmg, holder} = absorb_with_holder(ent, dmg, holder, school_mask)
        {ent, dmg, [holder | acc]}
      end)

    kept = new_holders |> Enum.reverse() |> Enum.reject(&exhausted_absorb?/1)

    entity =
      if kept == holders do
        entity
      else
        %{entity | unit: sync_unit(%{entity.unit | auras: kept})}
        |> Core.mark_broadcast_update()
      end

    {entity, remaining}
  end

  def absorb_damage(entity, damage, _school), do: {entity, damage}

  defp absorb_with_holder(entity, damage, %Holder{auras: auras} = holder, school_mask) do
    {entity, damage, new_auras} =
      Enum.reduce(auras, {entity, damage, []}, fn aura, {ent, dmg, acc} ->
        {ent, dmg, aura} = absorb_with_aura(ent, dmg, aura, school_mask)
        {ent, dmg, [aura | acc]}
      end)

    {entity, damage, %{holder | auras: Enum.reverse(new_auras)}}
  end

  defp absorb_with_aura(entity, damage, %Aura{type: :school_absorb, amount: amount} = aura, school_mask)
       when damage > 0 and is_integer(amount) and amount > 0 do
    if (aura.misc_value &&& school_mask) == 0 do
      {entity, damage, aura}
    else
      absorbed = min(amount, damage)
      {entity, damage - absorbed, %{aura | amount: amount - absorbed}}
    end
  end

  defp absorb_with_aura(
         %{unit: %Unit{power1: mana}} = entity,
         damage,
         %Aura{type: :mana_shield, amount: amount} = aura,
         _school_mask
       )
       when damage > 0 and is_integer(amount) and amount > 0 and is_integer(mana) and mana > 0 do
    absorbed = min(min(amount, damage), div(mana, @mana_per_absorbed_damage))

    if absorbed > 0 do
      entity = %{entity | unit: %{entity.unit | power1: mana - absorbed * @mana_per_absorbed_damage}}
      {entity, damage - absorbed, %{aura | amount: amount - absorbed}}
    else
      {entity, damage, aura}
    end
  end

  defp absorb_with_aura(entity, damage, aura, _school_mask), do: {entity, damage, aura}

  defp exhausted_absorb?(%Holder{auras: auras}) do
    absorbs = Enum.filter(auras, fn %Aura{type: type} -> type in @absorb_auras end)
    absorbs != [] and Enum.all?(absorbs, fn %Aura{amount: amount} -> amount <= 0 end)
  end

  def flat_modifier(%{unit: %Unit{auras: holders}}, type, school_mask) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.reduce(0, fn
      %Aura{type: ^type, amount: amount, misc_value: misc}, acc
      when is_integer(amount) and is_integer(misc) ->
        if (misc &&& school_mask) == 0, do: acc, else: acc + amount

      _aura, acc ->
        acc
    end)
  end

  def flat_modifier(_entity, _type, _school_mask), do: 0

  def auras_of_type(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.filter(&match?(%Aura{type: ^type}, &1))
  end

  def auras_of_type(_entity, _type), do: []

  def rooted?(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.any?(holders, &has_aura_type?(&1, :mod_root))
  end

  def rooted?(_entity), do: false

  def has_aura?(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    Enum.any?(holders, &has_aura_type?(&1, type))
  end

  def has_aura?(_entity, _type), do: false

  def has_spell?(%{unit: %Unit{auras: holders}}, spell_id) when is_list(holders) and is_integer(spell_id) do
    Enum.any?(holders, &match?(%Holder{spell: %Spell{id: ^spell_id}}, &1))
  end

  def has_spell?(_entity, _spell_id), do: false

  def confuse_anchor_key(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    case Enum.find(holders, &(has_aura_type?(&1, :mod_confuse) or has_aura_type?(&1, :mod_fear))) do
      %Holder{applied_at: applied_at, spell: %Spell{id: spell_id}} -> {spell_id, applied_at}
      _ -> nil
    end
  end

  def confuse_anchor_key(_entity), do: nil

  def break_on_damage(%{unit: %Unit{auras: holders}} = entity, now) when is_list(holders) and holders != [] do
    {removed, kept} =
      Enum.split_with(holders, fn holder ->
        has_aura_type?(holder, :mod_confuse) or interruptible?(holder, @aura_interrupt_damage)
      end)

    if removed == [] do
      entity
    else
      unit = sync_unit(%{entity.unit | auras: kept})

      {entity, events} =
        entity
        |> Map.put(:unit, unit)
        |> sync_movement_state(now)

      entity
      |> Core.mark_broadcast_update()
      |> Event.enqueue(events)
    end
  end

  def break_on_damage(entity, _now), do: entity

  defp has_aura_type?(%Holder{auras: auras}, type) do
    Enum.any?(auras, fn %Aura{type: t} -> t == type end)
  end

  defp sync_movement_flags(%{movement_block: %MovementBlock{} = mb, unit: %Unit{auras: holders}} = entity, now) do
    flags = mb.movement_flags || 0
    was_rooted? = (flags &&& @movement_flag_root) != 0
    has_root? = Enum.any?(holders, &(has_aura_type?(&1, :mod_root) or has_aura_type?(&1, :mod_stun)))

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
    entity = MovementStats.recompute(entity)
    {entity, events} = sync_movement_flags(entity, now)
    {entity, feather_events} = sync_movement_flag_aura(entity, :feather_fall, @movement_flag_safe_fall)
    {entity, hover_events} = sync_movement_flag_aura(entity, :hover, @movement_flag_hover)
    {entity, water_walk_events} = sync_movement_flag_aura(entity, :water_walk, @movement_flag_water_walk)
    entity = sync_stunned_flag(entity)
    flag_events = feather_events ++ hover_events ++ water_walk_events
    {entity, speed_change_events(entity, old_run_speed) ++ events ++ flag_events}
  end

  defp sync_movement_flag_aura(
         %{movement_block: %MovementBlock{} = mb, unit: %Unit{auras: holders}} = entity,
         type,
         bit
       )
       when is_list(holders) do
    flags = mb.movement_flags || 0
    was_on? = (flags &&& bit) != 0
    has_aura? = Enum.any?(holders, &has_aura_type?(&1, type))

    new_flags =
      if has_aura?,
        do: flags ||| bit,
        else: flags &&& bnot(bit)

    entity = %{entity | movement_block: %{mb | movement_flags: new_flags}}

    if has_aura? == was_on? do
      {entity, []}
    else
      {entity, [movement_flag_event(type, has_aura?)]}
    end
  end

  defp sync_movement_flag_aura(entity, _type, _bit), do: {entity, []}

  defp movement_flag_event(:feather_fall, enabled?), do: Event.feather_fall_changed(enabled?)
  defp movement_flag_event(:hover, enabled?), do: Event.hover_changed(enabled?)
  defp movement_flag_event(:water_walk, enabled?), do: Event.water_walk_changed(enabled?)

  defp sync_stunned_flag(%{unit: %Unit{auras: holders} = unit} = entity) when is_list(holders) do
    flags = unit.flags || 0
    stunned? = Enum.any?(holders, &has_aura_type?(&1, :mod_stun))

    new_flags =
      if stunned?,
        do: flags ||| @unit_flag_stunned,
        else: flags &&& bnot(@unit_flag_stunned)

    %{entity | unit: %{unit | flags: new_flags}}
  end

  defp sync_stunned_flag(entity), do: entity

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
    Enum.any?(current, &same_source?(&1, id, caster))
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

  defp tick_aura(entity, _holder, %Aura{type: :periodic_heal, next_tick_at: at} = aura, now)
       when is_integer(at) and now >= at do
    entity = Core.heal(entity, aura.amount)
    {entity, %{aura | next_tick_at: advance_tick(at, aura.amplitude_ms, now)}, []}
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

  defp advance_tick(last_tick, amplitude_ms, now) when is_integer(amplitude_ms) and amplitude_ms > 0 do
    next = last_tick + amplitude_ms
    if next > now, do: next, else: advance_tick(next, amplitude_ms, now)
  end

  defp advance_tick(_last_tick, _amplitude_ms, now), do: now + 1_000

  defp duration_event(%Holder{slot: slot, expires_at: expires_at}, now)
       when is_integer(slot) and is_integer(expires_at) and expires_at != -1 do
    [Event.aura_duration(slot, max(expires_at - now, 0))]
  end

  defp duration_event(_holder, _now), do: []

  def next_event_at(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.flat_map(&holder_event_times/1)
    |> Enum.min(fn -> nil end)
  end

  def next_event_at(_entity), do: nil

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
    amplitude_ms = effective_amplitude(effect)

    %Aura{
      index: effect.index,
      type: effect.aura,
      amount: Effect.damage_roll(effect),
      misc_value: effect.misc_value,
      multiple_value: effect.multiple_value,
      amplitude_ms: amplitude_ms,
      next_tick_at: next_tick(effect, amplitude_ms, now),
      trigger_spell_id: effect.trigger_spell_id
    }
  end

  defp effective_amplitude(%Effect{aura: :mod_power_regen_percent, amplitude_ms: amp}) do
    if is_integer(amp) and amp > 0, do: amp, else: @percent_regen_tick_ms
  end

  defp effective_amplitude(%Effect{aura: aura, amplitude_ms: amp}) when aura in @regen_auras do
    if is_integer(amp) and amp > 0, do: amp, else: @regen_tick_ms
  end

  defp effective_amplitude(%Effect{amplitude_ms: amp}), do: amp

  defp reaction_event(%Aura{type: type, trigger_spell_id: spell_id}, %Holder{} = holder, owner_guid, attacker_guid)
       when type in [:damage_shield, :proc_trigger_spell] and is_integer(spell_id) and spell_id > 0 do
    source_guid = holder.caster_guid || owner_guid
    source_level = holder.caster_level || 1
    [Event.trigger_spell(source_guid, source_level, attacker_guid, spell_id)]
  end

  defp reaction_event(_aura, _holder, _owner_guid, _attacker_guid), do: []

  defp next_tick(%Effect{aura: aura}, amplitude_ms, now)
       when aura in [:periodic_damage, :periodic_heal, :periodic_leech, :periodic_trigger_spell] and
              is_integer(amplitude_ms) and amplitude_ms > 0 do
    now + amplitude_ms
  end

  defp next_tick(_effect, _amplitude_ms, _now), do: nil

  defp next_free_slot(holders, negative?) do
    used = MapSet.new(holders, & &1.slot)
    range = if negative?, do: @max_positive_slots..(@max_slots - 1), else: 0..(@max_positive_slots - 1)
    Enum.find(range, &(not MapSet.member?(used, &1)))
  end

  def sync_unit(%Unit{} = unit) do
    unit
    |> Stats.recompute()
    |> sync_transform()
    |> sync_aura_fields()
  end

  defp sync_transform(%Unit{auras: holders} = unit) when is_list(holders) do
    transform =
      holders
      |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
      |> Enum.find(fn %Aura{type: type, misc_value: misc} -> type == :transform and is_integer(misc) and misc > 0 end)

    case {transform, unit.native_display_id} do
      {%Aura{misc_value: display_id}, _native} -> %{unit | display_id: display_id}
      {nil, native} when is_integer(native) and native > 0 -> %{unit | display_id: native}
      _ -> unit
    end
  end

  defp sync_transform(unit), do: unit

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
