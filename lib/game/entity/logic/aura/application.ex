defmodule ThistleTea.Game.Entity.Logic.Aura.Application do
  @moduledoc """
  Applies a cast spell's auras to an entity: builds the holder from the
  spell's aura effects (channeled periodic triggers are excluded — those tick
  through the channel, not as auras), enforces rank, same-source, exclusive-
  category, and mechanic-immunity stacking rules before handing the desired
  holders to the transition funnel.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Capacity
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.StackingProc
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.CreatureImmunity
  alias ThistleTea.Game.Entity.Logic.DiminishingReturns
  alias ThistleTea.Game.Entity.Logic.EffectImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Entity.Logic.TargetSpellPower
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts

  @negative_auras [
    :periodic_power_burn,
    :periodic_damage_percent,
    :periodic_damage,
    :periodic_leech,
    :mod_root,
    :mod_decrease_speed,
    :mod_stun,
    :mod_fear,
    :mod_confuse,
    :mod_possess,
    :mod_charm,
    :mod_detect_range,
    :mod_taunt
  ]

  @ignite_dot 12_654
  @ignite_max_stacks 5

  @regen_tick_ms 5000
  @percent_regen_tick_ms 2000
  @regen_auras [:mod_regen, :mod_power_regen, :mod_power_regen_percent]
  @context_auras [:periodic_power_burn, :periodic_trigger_spell, :proc_trigger_spell, :damage_shield]
  @periodic_auras [
    :periodic_power_burn,
    :periodic_damage_percent,
    :periodic_damage,
    :periodic_heal,
    :periodic_energize,
    :periodic_leech,
    :periodic_health_funnel,
    :periodic_mana_leech,
    :periodic_trigger_spell,
    :obs_mod_health,
    :obs_mod_mana
  ]

  def apply_spell(entity, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    if CreatureImmunity.spell?(entity, context, spell),
      do: {entity, []},
      else: apply_unblocked_spell(entity, context, spell, now)
  end

  defp apply_unblocked_spell(entity, context, spell, now) do
    case build_auras(entity, context, spell, now) do
      [] ->
        {entity, []}

      auras ->
        target_guid = entity.object.guid

        holder = %Holder{
          spell: modified_holder_spell(spell, context),
          caster_guid: context.caster_guid,
          caster_totem?: context.caster_totem?,
          cast_item_guid: context.cast_item_guid,
          triggered?: context.triggered?,
          cooldown_started_at: context.cooldown_started_at,
          caster_owner_guid: context.caster_owner_guid,
          reflected_by_guid: context.reflected_by_guid,
          caster_level: context.caster_level,
          caster_faction_template: context.caster_faction_template,
          resistance_penetration: context.resistance_penetration,
          cast_context: if(Enum.any?(auras, &(&1.type in @context_auras)), do: context),
          applied_at: now,
          expires_at: expires_at(now, effective_duration(spell, context)),
          charges: holder_charges(spell),
          area_radius: area_radius(spell),
          next_area_refresh_at: next_area_refresh_at(spell, context, target_guid, now),
          auras: auras,
          negative?: negative?(spell, auras, context, target_guid)
        }

        do_apply(entity, holder, context, now)
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

  def dispel_immune?(%{unit: %Unit{auras: holders}}, %Spell{dispel_type: dispel_type})
      when is_list(holders) and is_integer(dispel_type) and dispel_type > 0 do
    blocked_by_dispel_immunity?(holders, dispel_type)
  end

  def dispel_immune?(_entity, _spell), do: false

  def equipment_holder(entity, %Spell{} = spell, source, now) do
    %{passive_holder(entity, spell, now) | item_source: source}
  end

  def linked_holder(entity, %Spell{} = spell, source, now) do
    %{
      passive_holder(entity, spell, now)
      | linked_from: source,
        expires_at: expires_at(now, spell.duration_ms),
        charges: holder_charges(spell)
    }
  end

  defp passive_holder(entity, %Spell{} = spell, now) do
    context = %CastContext{caster_guid: entity.object.guid, caster_level: entity.unit.level || 1}

    %Holder{
      spell: %{spell | attributes: MapSet.put(spell.attributes, :passive), spell_visual: 0},
      caster_guid: context.caster_guid,
      caster_level: context.caster_level,
      applied_at: now,
      auras: build_auras(entity, context, spell, now)
    }
  end

  defp blocked_by_dispel_immunity?(holders, dispel_type)
       when is_list(holders) and is_integer(dispel_type) and dispel_type > 0 do
    Enum.any?(holders, fn %Holder{auras: auras} ->
      Enum.any?(auras, &match?(%Aura{type: :dispel_immunity, misc_value: ^dispel_type}, &1))
    end)
  end

  defp blocked_by_dispel_immunity?(_holders, _dispel_type), do: false

  defp negative?(spell, auras, %CastContext{} = context, target_guid) do
    cond do
      Spell.attribute?(spell, :negative) -> true
      context.caster_guid == target_guid -> false
      context.target_hostile? == true and Spell.harmful?(spell) -> true
      Enum.any?(auras, fn %Aura{type: type} -> type in @negative_auras end) -> true
      Enum.any?(auras, &negative_resistance_modifier?/1) -> true
      true -> false
    end
  end

  defp negative_resistance_modifier?(%Aura{type: type, amount: amount}) do
    type in [:mod_resistance, :mod_resistance_exclusive] and is_number(amount) and amount < 0
  end

  defp do_apply(%{unit: %Unit{auras: existing}} = entity, %Holder{} = holder, context, now) when is_list(existing) do
    cond do
      blocked_by_stronger_rank?(existing, holder.spell) ->
        {entity, []}

      blocked_by_mechanic_immunity?(existing, holder.spell) ->
        consume_immunity_charge(entity, holder.spell, now)

      blocked_by_dispel_immunity?(existing, holder.spell.dispel_type) ->
        {entity, []}

      true ->
        apply_unblocked(entity, existing, holder, context, now)
    end
  end

  defp do_apply(entity, %Holder{} = holder, context, now) do
    apply_unblocked(entity, [], holder, context, now)
  end

  defp apply_diminished(entity, holders, holder, context, now) do
    case DiminishingReturns.apply(entity, holder, context, now) do
      {:ok, entity, diminished} ->
        holders =
          Enum.map(holders, fn
            ^holder -> diminished
            current -> current
          end)

        Transition.run(entity, %Change{holders: holders, cause: :applied, now: now})

      {:immune, entity} ->
        {entity, [Effects.spell_log_miss(context.caster_guid, entity.object.guid, holder.spell.id, :immune)]}
    end
  end

  defp apply_unblocked(entity, existing, %Holder{} = holder, context, now) do
    case StackingProc.prepare(holder, existing) do
      nil -> {entity, []}
      holder -> upsert_unblocked(entity, existing, holder, context, now)
    end
  end

  defp upsert_unblocked(entity, existing, %Holder{} = holder, context, now) do
    existing =
      existing
      |> remove_immune_mechanics(holder)
      |> EffectImmunity.purge(holder)

    holders =
      if holder.spell.id == @ignite_dot do
        upsert_ignite(existing, holder)
      else
        existing
        |> remove_non_stacking(holder)
        |> upsert_holder(holder)
      end

    holders = Capacity.retain(holders, entity.object.guid)

    case Enum.find(holders, &Holder.same_source?(&1, holder.spell.id, holder.caster_guid)) do
      nil -> Transition.run(entity, %Change{holders: holders, cause: :applied, now: now})
      applied -> apply_diminished(entity, holders, applied, context, now)
    end
  end

  defp remove_non_stacking(holders, %Holder{} = incoming) do
    shapeshift? = Holder.has_aura_type?(incoming, :mod_shapeshift)
    Enum.reject(holders, &non_stacking?(&1, incoming, shapeshift?))
  end

  defp non_stacking?(%Holder{linked_from: source}, _incoming, _shapeshift?) when not is_nil(source), do: false

  defp non_stacking?(
         %Holder{spell: %Spell{} = other} = existing,
         %Holder{spell: %Spell{} = spell} = incoming,
         shapeshift?
       ) do
    cond do
      exclusive_category_conflict?(existing, incoming) -> true
      shapeshift? and Holder.has_aura_type?(existing, :mod_shapeshift) -> true
      mount_conflict?(existing, incoming) -> true
      other.id == spell.id and existing.caster_guid != incoming.caster_guid -> replaces_same_spell?(existing, incoming)
      Spell.same_chain?(other, spell) -> replaces_chain_rank?(existing, incoming)
      true -> false
    end
  end

  defp mount_conflict?(existing, incoming) do
    Holder.has_aura_type?(incoming, :mounted) and Holder.has_aura_type?(existing, :mounted)
  end

  defp replaces_same_spell?(existing, %Holder{spell: spell} = incoming) do
    not Spell.custom?(spell, :allow_stack_between_caster) and not cross_caster_coexist?(existing, incoming)
  end

  defp replaces_chain_rank?(existing, %Holder{spell: spell} = incoming) do
    existing.caster_guid == incoming.caster_guid or
      Spell.custom?(spell, :allow_stack_between_caster) or
      not cross_caster_coexist?(existing, incoming)
  end

  @personal_stack_auras [
    :dummy,
    :periodic_damage_percent,
    :periodic_damage,
    :periodic_leech,
    :periodic_health_funnel,
    :periodic_heal,
    :periodic_mana_leech,
    :channel_death_item
  ]

  defp cross_caster_coexist?(%Holder{} = existing, %Holder{spell: %Spell{} = spell} = incoming) do
    Spell.attribute?(spell, :channeled) or
      Spell.custom?(spell, :separate_aura_per_caster) or
      Spell.attribute?(spell, :dot_stacking_rule) or
      personal_overlap_only?(existing, incoming)
  end

  defp personal_overlap_only?(%Holder{auras: existing_auras}, %Holder{auras: incoming_auras}) do
    existing_indexes = MapSet.new(existing_auras, & &1.index)

    incoming_auras
    |> Enum.filter(&MapSet.member?(existing_indexes, &1.index))
    |> Enum.all?(&(&1.type in @personal_stack_auras))
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

  defp exclusive_category_conflict?(
         %Holder{spell: %Spell{exclusive_category: :hunter_sting}, caster_guid: existing_caster},
         %Holder{spell: %Spell{exclusive_category: :hunter_sting}, caster_guid: incoming_caster}
       ) do
    existing_caster == incoming_caster
  end

  defp exclusive_category_conflict?(
         %Holder{spell: %Spell{exclusive_category: :paladin_judgement}, caster_guid: existing_caster},
         %Holder{spell: %Spell{exclusive_category: :paladin_judgement}, caster_guid: incoming_caster}
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

  defp consume_immunity_charge(%{unit: %Unit{auras: holders}} = entity, %Spell{mechanic: mechanic}, now) do
    case Enum.find_index(holders, &(&1.charges != nil and immunity_holder_for_mechanic?(&1, mechanic))) do
      nil ->
        {entity, []}

      index ->
        holders = spend_holder_charge(holders, index)
        Transition.run(entity, %Change{holders: holders, cause: :consumed, now: now})
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

  defp upsert_holder(existing, %Holder{spell: %Spell{id: spell_id} = spell, caster_guid: caster_guid} = incoming) do
    index =
      Enum.find_index(existing, &(is_nil(&1.linked_from) and Holder.same_source?(&1, spell_id, caster_guid))) ||
        shared_stack_index(existing, spell)

    case index do
      nil ->
        existing ++ [%{incoming | slot: nil}]

      index ->
        old = Enum.at(existing, index)

        refreshed = %{
          incoming
          | slot: nil,
            stacks: next_stacks(old, incoming),
            next_proc_at: old.next_proc_at,
            auras: carry_tick_times(old.auras, incoming.auras)
        }

        List.replace_at(existing, index, refreshed)
    end
  end

  defp upsert_ignite(existing, %Holder{} = incoming) do
    case Enum.find_index(existing, &match?(%Holder{spell: %Spell{id: @ignite_dot}}, &1)) do
      nil ->
        existing ++ [%{incoming | slot: nil}]

      index ->
        current = Enum.at(existing, index)

        refreshed =
          if ignite_finished?(current) do
            %{incoming | slot: current.slot}
          else
            refresh_ignite(current, incoming)
          end

        List.replace_at(existing, index, refreshed)
    end
  end

  defp refresh_ignite(%Holder{} = current, %Holder{} = incoming) do
    add_amount? = current.stacks < @ignite_max_stacks

    %{
      current
      | applied_at: incoming.applied_at,
        expires_at: incoming.expires_at,
        stacks: min(current.stacks + 1, @ignite_max_stacks),
        auras: refresh_ignite_auras(current.auras, incoming.auras, add_amount?)
    }
  end

  defp refresh_ignite_auras(current, incoming, add_amount?) do
    Enum.map(incoming, fn %Aura{} = aura ->
      case Enum.find(current, &(&1.index == aura.index and &1.type == aura.type)) do
        %Aura{amount: current_amount} when add_amount? and is_integer(current_amount) and is_integer(aura.amount) ->
          %{aura | amount: current_amount + aura.amount}

        %Aura{amount: current_amount} when is_integer(current_amount) ->
          %{aura | amount: current_amount}

        _current_aura ->
          aura
      end
    end)
  end

  defp ignite_finished?(%Holder{expires_at: expires_at, auras: auras}) when is_integer(expires_at) do
    Enum.any?(auras, fn
      %Aura{type: :periodic_damage, next_tick_at: next_tick_at} when is_integer(next_tick_at) ->
        next_tick_at > expires_at

      _aura ->
        false
    end)
  end

  defp ignite_finished?(_holder), do: false

  defp shared_stack_index(existing, %Spell{id: spell_id} = spell) do
    if Spell.custom?(spell, :allow_stack_between_caster) do
      Enum.find_index(existing, &(&1.spell.id == spell_id and is_nil(&1.linked_from)))
    end
  end

  defp next_stacks(%Holder{stacks: stacks}, %Holder{spell: %Spell{stack_amount: cap}, stacks: incoming_stacks})
       when is_integer(cap) and cap > 1 do
    min((stacks || 1) + incoming_stacks, cap)
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

  defp expires_at(_now, 0), do: nil
  defp expires_at(_now, nil), do: nil
  defp expires_at(_now, -1), do: -1
  defp expires_at(now, duration_ms) when is_integer(duration_ms), do: now + duration_ms

  defp effective_duration(%Spell{} = spell, %CastContext{} = context) do
    spell
    |> base_duration(context)
    |> modified_duration(context)
  end

  defp base_duration(%Spell{} = spell, %CastContext{combo_points: points}) when is_integer(points) and points > 0 do
    Spell.duration_for_combo_points(spell, points)
  end

  defp base_duration(%Spell{} = spell, %CastContext{caster_guid: caster, target_guid: target}) when caster != target do
    if area_radius(spell), do: 2_500, else: spell.duration_ms
  end

  defp base_duration(%Spell{duration_ms: duration_ms}, _context), do: duration_ms

  defp modified_duration(duration, %CastContext{} = context) when is_integer(duration) and duration > 0 do
    round(Modifiers.value(context.spell_modifiers, :duration, duration))
  end

  defp modified_duration(duration, _context), do: duration

  defp modified_holder_spell(%Spell{} = spell, %CastContext{} = context) do
    proc_chance = Modifiers.value(context.spell_modifiers, :chance_of_success, spell.proc_chance || 0)
    if proc_chance == spell.proc_chance, do: spell, else: %{spell | proc_chance: proc_chance}
  end

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
    |> Enum.reject(
      &(EffectImmunity.blocked?(entity, spell, &1) or CreatureImmunity.effect?(entity, context, spell, &1) or
          channel_ticked?(spell, &1))
    )
    |> Enum.reduce([], fn effect, acc ->
      case build_aura(entity, spell, effect, amount_override, context, now) do
        nil -> acc
        aura -> [aura | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp channel_ticked?(%Spell{} = spell, %Effect{aura: :periodic_trigger_spell}) do
    Spell.attribute?(spell, :channeled)
  end

  defp channel_ticked?(_spell, _effect), do: false

  defp build_aura(_entity, _spell, %Effect{aura: nil}, _amount_override, _context, _now), do: nil

  defp build_aura(
         %{internal: %{totem: %Totem{}}},
         _spell,
         %Effect{type: :apply_area_aura, index: index},
         _amount_override,
         _context,
         _now
       ), do: %Aura{index: index, type: :none, amount: 0}

  defp build_aura(entity, %Spell{} = spell, %Effect{} = effect, amount_override, %CastContext{} = context, now) do
    amplitude_ms = effective_amplitude(effect)

    %Aura{
      index: effect.index,
      type: effect.aura,
      amount: modified_aura_amount(entity, spell, effect, amount_override, context),
      misc_value: effect.misc_value,
      multiple_value: transfer_multiplier(effect, context),
      class_mask: effect.class_mask,
      item_type: effect.item_type,
      amplitude_ms: amplitude_ms,
      next_tick_at: next_tick(spell, effect, amplitude_ms, now),
      trigger_spell_id: effect.trigger_spell_id
    }
  end

  defp aura_amount(%Spell{}, %Effect{}, amount_override, _context) when is_integer(amount_override), do: amount_override

  defp aura_amount(%Spell{} = spell, %Effect{} = effect, _amount_override, %CastContext{} = context) do
    level_units = Spell.level_units(spell, context.caster_level)
    combo_points = finisher_combo_points(spell, context)

    if combo_points > 0 do
      Effect.amount(effect, level_units, combo_points)
    else
      Effect.roll(effect, level_units)
    end
  end

  defp finisher_combo_points(%Spell{} = spell, %CastContext{combo_points: points}) do
    if Scripts.finisher?(spell) and is_integer(points), do: max(points, 0), else: 0
  end

  defp modified_aura_amount(entity, %Spell{} = spell, %Effect{} = effect, amount_override, %CastContext{} = context) do
    amount = aura_amount(spell, effect, amount_override, context)
    amount = modify_aura_base_amount(effect.aura, amount, context)
    amount = amount + periodic_benefit(entity, spell, effect, context)

    multiplier =
      case effect.aura do
        aura when aura in [:periodic_damage, :periodic_leech, :periodic_health_funnel, :periodic_mana_leech] ->
          context.effect_damage_multiplier

        :periodic_heal ->
          context.effect_healing_multiplier

        _aura ->
          1.0
      end

    amount =
      if effect.aura in [
           :periodic_damage,
           :periodic_leech,
           :periodic_health_funnel,
           :periodic_mana_leech,
           :periodic_heal
         ] do
        Modifiers.value(context.spell_modifiers, :dot, amount * 1.0)
      else
        Modifiers.value(context.spell_modifiers, :all_effects, amount)
      end

    amount =
      if effect.aura in [:periodic_damage, :periodic_leech, :periodic_health_funnel],
        do: periodic_done_amount(entity, spell, context, amount) * context.happiness_multiplier,
        else: amount

    trunc(amount * (multiplier || 1.0))
  end

  defp periodic_done_amount(entity, %Spell{} = spell, %CastContext{} = context, amount) do
    if Spell.custom?(spell, :fixed_damage) or Spell.attribute?(spell, :ignore_caster_modifiers) or
         spell.id == @ignite_dot do
      amount
    else
      versus = max(100 + TargetDamage.bonus(entity, context.damage_done_versus), 0) / 100
      amount * (context.damage_done_multiplier || 1.0) * versus
    end
  end

  defp modify_aura_base_amount(aura, amount, %CastContext{} = context)
       when aura in [:mod_increase_speed, :mod_decrease_speed, :mod_increase_swim_speed] do
    Modifiers.value(context.spell_modifiers, :speed, amount)
  end

  defp modify_aura_base_amount(:reflect_spells_school, amount, %CastContext{} = context) do
    amount + (context.reflect_chance_bonus || 0)
  end

  defp modify_aura_base_amount(_aura, amount, _context), do: amount

  defp periodic_benefit(entity, %Spell{} = spell, %Effect{aura: aura} = effect, %CastContext{} = context)
       when aura in [:periodic_damage, :periodic_leech, :periodic_health_funnel] do
    Coefficient.bonus(TargetSpellPower.benefit(entity, context, spell), spell, effect, :dot) +
      TargetDamage.spell_bonus(entity, context.target_damage, spell, effect, :dot)
  end

  defp periodic_benefit(_entity, %Spell{} = spell, %Effect{aura: :periodic_heal} = effect, %CastContext{} = context) do
    Coefficient.bonus(context.healing_bonus || 0, spell, effect, :dot)
  end

  defp periodic_benefit(_entity, _spell, _effect, _context), do: 0

  defp transfer_multiplier(%Effect{aura: aura, multiple_value: value}, %CastContext{} = context)
       when aura in [:periodic_leech, :periodic_health_funnel] do
    base = if is_number(value) and value > 0, do: value, else: 1.0
    max(Modifiers.value(context.spell_modifiers, :multiple_value, base), 0.0)
  end

  defp transfer_multiplier(%Effect{multiple_value: value}, _context), do: value

  defp effective_amplitude(%Effect{aura: :mod_power_regen_percent, amplitude_ms: amp}) do
    if is_integer(amp) and amp > 0, do: amp, else: @percent_regen_tick_ms
  end

  defp effective_amplitude(%Effect{aura: :obs_mod_mana, amplitude_ms: amp}) do
    if is_integer(amp) and amp > 0, do: amp, else: 1_000
  end

  defp effective_amplitude(%Effect{aura: aura, amplitude_ms: amp}) when aura in @regen_auras do
    if is_integer(amp) and amp > 0, do: amp, else: @regen_tick_ms
  end

  defp effective_amplitude(%Effect{amplitude_ms: amp}), do: amp

  defp next_tick(spell, %Effect{aura: aura}, amplitude_ms, now)
       when aura in @periodic_auras and is_integer(amplitude_ms) and amplitude_ms > 0 do
    now + Scripts.initial_periodic_delay(spell, amplitude_ms)
  end

  defp next_tick(_spell, _effect, _amplitude_ms, _now), do: nil
end
