defmodule ThistleTea.Game.Entity.Logic.Aura.Application do
  @moduledoc """
  Applies a cast spell's auras to an entity: builds the holder from the
  spell's aura effects (channeled periodic triggers are excluded — those tick
  through the channel, not as auras), enforces rank, same-source, exclusive-
  category, and mechanic-immunity stacking rules, and allocates display slots
  via upsert-or-refresh.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Lifecycle
  alias ThistleTea.Game.Entity.Logic.Aura.MovementSync
  alias ThistleTea.Game.Entity.Logic.Aura.PlayerSync
  alias ThistleTea.Game.Entity.Logic.Aura.StealthSync
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts

  @negative_auras [
    :periodic_damage,
    :periodic_leech,
    :mod_root,
    :mod_decrease_speed,
    :mod_stun,
    :mod_fear,
    :mod_confuse,
    :mod_possess,
    :mod_detect_range,
    :mod_taunt
  ]

  @aura_interrupt_not_seated 0x40000

  @regen_tick_ms 5000
  @percent_regen_tick_ms 2000
  @regen_auras [:mod_regen, :mod_power_regen, :mod_power_regen_percent]
  @periodic_auras [
    :periodic_damage,
    :periodic_heal,
    :periodic_energize,
    :periodic_leech,
    :periodic_trigger_spell
  ]

  @stand_state_sit 1

  def apply_spell(entity, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    case build_auras(entity, context, spell, now) do
      [] ->
        {entity, []}

      auras ->
        target_guid = entity.object.guid

        holder = %Holder{
          spell: spell,
          caster_guid: context.caster_guid,
          caster_level: context.caster_level,
          applied_at: now,
          expires_at: expires_at(now, effective_duration(spell, context)),
          charges: holder_charges(spell),
          area_radius: area_radius(spell),
          next_area_refresh_at: next_area_refresh_at(spell, context, target_guid, now),
          auras: auras,
          negative?: negative?(spell, auras, context, target_guid)
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

  def blocked_by_stronger_rank?(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    blocked_by_stronger_rank?(holders, spell)
  end

  def blocked_by_stronger_rank?(holders, %Spell{} = spell) when is_list(holders) do
    Enum.any?(holders, fn %Holder{spell: other} -> Spell.stronger_rank_of_same_chain?(other, spell) end)
  end

  def blocked_by_stronger_rank?(_entity, _spell), do: false

  def mechanic_immune?(%{unit: %Unit{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    blocked_by_mechanic_immunity?(holders, spell)
  end

  def mechanic_immune?(_entity, _spell), do: false

  defp negative?(spell, auras, %CastContext{} = context, target_guid) do
    cond do
      Spell.attribute?(spell, :negative) -> true
      context.caster_guid == target_guid -> false
      context.target_hostile? == true and Spell.requires_hostile_target?(spell) -> true
      Enum.any?(auras, fn %Aura{type: type} -> type in @negative_auras end) -> true
      Enum.any?(auras, &negative_resistance_modifier?/1) -> true
      true -> false
    end
  end

  defp negative_resistance_modifier?(%Aura{type: type, amount: amount}) do
    type in [:mod_resistance, :mod_resistance_exclusive] and is_number(amount) and amount < 0
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
    unit = UnitSync.sync_unit(%{entity.unit | auras: holders})

    {entity, sit_events} =
      %{entity | unit: unit}
      |> PlayerSync.sync()
      |> StealthSync.sync()
      |> maybe_reset_shapeshift_rage(holder)
      |> maybe_heal_increased_health(holder)
      |> maybe_sit(holder)

    {entity, events} = MovementSync.sync_movement_state(entity, now)
    duration_events = applied_duration_events(entity, holder, now)

    {Core.mark_broadcast_update(entity), sit_events ++ events ++ duration_events}
  end

  defp applied_duration_events(
         %Character{unit: %Unit{auras: holders}},
         %Holder{spell: %Spell{id: spell_id}, caster_guid: caster_guid},
         now
       ) do
    holders
    |> Enum.find(&Holder.same_source?(&1, spell_id, caster_guid))
    |> Lifecycle.duration_event(now)
  end

  defp applied_duration_events(_entity, _holder, _now), do: []

  defp remove_non_stacking(holders, %Holder{spell: %Spell{} = spell, caster_guid: caster_guid} = incoming) do
    shapeshift? = Holder.has_aura_type?(incoming, :mod_shapeshift)

    Enum.reject(holders, fn %Holder{spell: %Spell{} = other} = existing ->
      Spell.same_chain?(other, spell) or
        exclusive_category_conflict?(existing, incoming) or
        (other.id == spell.id and existing.caster_guid != caster_guid) or
        (shapeshift? and Holder.has_aura_type?(existing, :mod_shapeshift))
    end)
  end

  defp exclusive_category_conflict?(
         %Holder{spell: %Spell{exclusive_category: :paladin_blessing}, caster_guid: existing_caster},
         %Holder{spell: %Spell{exclusive_category: :paladin_blessing}, caster_guid: incoming_caster}
       ) do
    existing_caster == incoming_caster
  end

  defp exclusive_category_conflict?(
         %Holder{spell: %Spell{exclusive_category: :warlock_curse}, caster_guid: existing_caster},
         %Holder{spell: %Spell{exclusive_category: :warlock_curse}, caster_guid: incoming_caster}
       ) do
    existing_caster == incoming_caster
  end

  defp exclusive_category_conflict?(%Holder{spell: existing}, %Holder{spell: incoming}) do
    Spell.same_exclusive_category?(existing, incoming)
  end

  defp holder_charges(%Spell{proc_charges: charges}) when is_integer(charges) and charges > 0, do: charges
  defp holder_charges(_spell), do: nil

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

        %{entity | unit: UnitSync.sync_unit(%{entity.unit | auras: holders})}
        |> PlayerSync.sync()
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
      types -> Enum.reject(holders, &Holder.has_any_type?(&1, types))
    end
  end

  defp mechanic_aura_types(5), do: [:mod_fear]
  defp mechanic_aura_types(7), do: [:mod_root]
  defp mechanic_aura_types(11), do: [:mod_decrease_speed]
  defp mechanic_aura_types(12), do: [:mod_stun]
  defp mechanic_aura_types(_), do: []

  defp upsert_holder(existing, %Holder{spell: %Spell{id: spell_id}, caster_guid: caster_guid} = incoming) do
    case Enum.find_index(existing, &Holder.same_source?(&1, spell_id, caster_guid)) do
      nil ->
        slot = UnitSync.next_free_slot(existing, incoming.negative?)
        existing ++ [%{incoming | slot: slot}]

      index ->
        old = Enum.at(existing, index)

        refreshed = %{
          incoming
          | slot: old.slot,
            stacks: next_stacks(old, incoming),
            auras: carry_tick_times(old.auras, incoming.auras)
        }

        List.replace_at(existing, index, refreshed)
    end
  end

  defp next_stacks(%Holder{stacks: stacks}, %Holder{spell: %Spell{stack_amount: cap}})
       when is_integer(cap) and cap > 1 do
    min((stacks || 1) + 1, cap)
  end

  defp next_stacks(_old, _incoming), do: 1

  defp carry_tick_times(old_auras, new_auras) do
    Enum.map(new_auras, fn %Aura{} = aura ->
      case Enum.find(old_auras, &(&1.index == aura.index and &1.type == aura.type)) do
        %Aura{next_tick_at: at} when is_integer(at) -> %{aura | next_tick_at: at}
        _ -> aura
      end
    end)
  end

  defp maybe_reset_shapeshift_rage(%{unit: %Unit{power_type: 1, power2: rage} = unit} = entity, %Holder{} = holder) do
    if Holder.has_aura_type?(holder, :mod_shapeshift) and is_integer(rage) and rage > 0 do
      %{entity | unit: %{unit | power2: 0}}
    else
      entity
    end
  end

  defp maybe_reset_shapeshift_rage(entity, _holder), do: entity

  defp maybe_heal_increased_health(entity, %Holder{auras: auras}) do
    auras
    |> Enum.reduce(0, fn
      %Aura{type: :mod_increase_health, amount: amount}, acc when is_integer(amount) and amount > 0 -> acc + amount
      _aura, acc -> acc
    end)
    |> case do
      0 -> entity
      amount -> Core.heal(entity, amount)
    end
  end

  defp maybe_sit(%{unit: %Unit{stand_state: stand_state} = unit} = entity, %Holder{spell: %Spell{} = spell}) do
    if (spell.aura_interrupt_flags &&& @aura_interrupt_not_seated) != 0 and stand_state != @stand_state_sit do
      {%{entity | unit: %{unit | stand_state: @stand_state_sit}}, [Event.stand_state(@stand_state_sit)]}
    else
      {entity, []}
    end
  end

  defp maybe_sit(entity, _holder), do: {entity, []}

  defp expires_at(_now, 0), do: nil
  defp expires_at(_now, nil), do: nil
  defp expires_at(_now, -1), do: -1
  defp expires_at(now, duration_ms) when is_integer(duration_ms), do: now + duration_ms

  defp effective_duration(%Spell{} = spell, %CastContext{combo_points: points})
       when is_integer(points) and points > 0 do
    Spell.duration_for_combo_points(spell, points)
  end

  defp effective_duration(%Spell{} = spell, %CastContext{caster_guid: caster, target_guid: target})
       when caster != target do
    if area_radius(spell), do: 2_500, else: spell.duration_ms
  end

  defp effective_duration(%Spell{duration_ms: duration_ms}, _context), do: duration_ms

  defp area_radius(%Spell{effects: effects}) do
    effects
    |> Enum.filter(&match?(%Effect{type: :apply_area_aura}, &1))
    |> Enum.map(& &1.radius_yards)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> nil end)
  end

  defp next_area_refresh_at(%Spell{} = spell, %CastContext{caster_guid: caster_guid}, caster_guid, now) do
    if area_radius(spell), do: now + 1_000
  end

  defp next_area_refresh_at(_spell, _context, _target_guid, _now), do: nil

  defp build_auras(entity, %CastContext{} = context, %Spell{} = spell, now) do
    amount_override = Scripts.aura_amount_override(spell, entity)

    spell
    |> Spell.aura_effects()
    |> Enum.reject(&channel_ticked?(spell, &1))
    |> Enum.reduce([], fn effect, acc ->
      case build_aura(effect, finisher_amount(spell, context, amount_override), now) do
        nil -> acc
        aura -> [aura | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp finisher_amount(_spell, _context, amount) when is_integer(amount), do: amount

  defp finisher_amount(%Spell{} = spell, %CastContext{combo_points: points}, nil)
       when is_integer(points) and points > 0 do
    {:finisher, spell, points}
  end

  defp finisher_amount(_spell, _context, amount), do: amount

  defp channel_ticked?(%Spell{} = spell, %Effect{aura: :periodic_trigger_spell}) do
    Spell.attribute?(spell, :channeled)
  end

  defp channel_ticked?(_spell, _effect), do: false

  defp build_aura(%Effect{aura: nil}, _amount_override, _now), do: nil

  defp build_aura(%Effect{} = effect, amount_override, now) do
    amplitude_ms = effective_amplitude(effect)

    %Aura{
      index: effect.index,
      type: effect.aura,
      amount: aura_amount(effect, amount_override),
      misc_value: effect.misc_value,
      multiple_value: effect.multiple_value,
      amplitude_ms: amplitude_ms,
      next_tick_at: next_tick(effect, amplitude_ms, now),
      trigger_spell_id: effect.trigger_spell_id
    }
  end

  defp aura_amount(%Effect{} = effect, {:finisher, spell, points}) do
    if Scripts.finisher?(spell), do: Effect.amount(effect, points), else: Effect.damage_roll(effect)
  end

  defp aura_amount(%Effect{} = effect, amount_override), do: amount_override || Effect.damage_roll(effect)

  defp effective_amplitude(%Effect{aura: :mod_power_regen_percent, amplitude_ms: amp}) do
    if is_integer(amp) and amp > 0, do: amp, else: @percent_regen_tick_ms
  end

  defp effective_amplitude(%Effect{aura: aura, amplitude_ms: amp}) when aura in @regen_auras do
    if is_integer(amp) and amp > 0, do: amp, else: @regen_tick_ms
  end

  defp effective_amplitude(%Effect{amplitude_ms: amp}), do: amp

  defp next_tick(%Effect{aura: aura}, amplitude_ms, now)
       when aura in @periodic_auras and is_integer(amplitude_ms) and amplitude_ms > 0 do
    now + amplitude_ms
  end

  defp next_tick(_effect, _amplitude_ms, _now), do: nil
end
