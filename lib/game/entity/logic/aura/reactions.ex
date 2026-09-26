defmodule ThistleTea.Game.Entity.Logic.Aura.Reactions do
  @moduledoc """
  On-hit aura reactions: damage shields and proc triggers fire back at the
  attacker, and charge-limited holders spend a charge per hit taken.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.ClassScript
  alias ThistleTea.Game.Entity.Logic.Aura.HealingPower
  alias ThistleTea.Game.Entity.Logic.Aura.ProcSpell
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.Scripts

  @charge_consuming_on_hit [
    :damage_shield,
    :proc_trigger_spell,
    :proc_trigger_damage,
    :mod_block_percent,
    :mod_resistance,
    :mod_resistance_exclusive
  ]

  def reactions(entity, :hit_taken, %{attacker_guid: attacker_guid} = context)
      when is_integer(attacker_guid) and not is_map_key(context, :proc_type) do
    reactions(entity, :hit_taken, Map.merge(context, %{proc_type: :take_melee_swing, outcome: :normal}))
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :hit_taken,
        %{attacker_guid: attacker_guid, proc_type: proc_type, outcome: outcome} = context
      )
      when is_list(holders) and is_integer(attacker_guid) and
             proc_type in [:take_melee_swing, :take_melee_ability, :take_ranged_attack, :take_ranged_ability] and
             is_atom(outcome) do
    triggering_spell = Map.get(context, :spell)

    {holders, events} =
      Enum.map_reduce(holders, [], fn %Holder{} = holder, events ->
        {holder, holder_events} =
          incoming_reaction(entity, holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome, context)

        {holder, events ++ holder_events}
      end)

    {entity, removal_events} = transition_holders(entity, Enum.reject(holders, &is_nil/1), context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        event,
        %{spell: %Spell{} = triggering_spell, outcome: outcome, proc_type: proc_type} = context
      )
      when is_list(holders) and event in [:spell_hit_dealt, :spell_cast_completed] and
             outcome in [:normal, :crit, :cast_end] and
             proc_type in [
               :deal_harmful_spell,
               :deal_harmful_ability,
               :deal_harmful_periodic,
               :deal_helpful_spell,
               :deal_helpful_ability,
               :deal_helpful_periodic,
               :deal_ranged_attack,
               :deal_ranged_ability,
               :deal_melee_ability
             ] do
    {holders, events} =
      Enum.reduce(holders, {holders, []}, fn %Holder{} = holder, {current_holders, events} ->
        outgoing_proc_transition(
          current_holders,
          events,
          holder,
          owner_guid,
          triggering_spell,
          proc_type,
          context
        )
      end)

    {entity, removal_events} = transition_holders(entity, holders, context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :melee_hit_dealt,
        %{victim_guid: victim_guid, outcome: outcome, proc_type: proc_type, now: now} = context
      )
      when is_list(holders) and is_integer(victim_guid) and is_integer(now) and is_atom(outcome) and
             proc_type in [:deal_melee_swing, :deal_melee_ability] do
    {holders, events} =
      Enum.map_reduce(holders, [], fn %Holder{} = holder, events ->
        {holder, holder_events} =
          outgoing_melee_reaction(
            holder,
            owner_guid,
            victim_guid,
            context
          )

        {holder, events ++ holder_events}
      end)

    {entity, removal_events} = transition_holders(entity, Enum.reject(holders, &is_nil/1), context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :spell_hit_taken,
        %{attacker_guid: attacker_guid, spell: %Spell{}, proc_type: proc_type, outcome: outcome} = context
      )
      when is_list(holders) and is_integer(attacker_guid) and outcome in [:normal, :crit, :resist, :reflect] and
             proc_type in [:take_harmful_spell, :take_harmful_periodic] do
    context =
      Map.merge(context, %{
        owner_max_health: entity.unit.max_health,
        owner_max_mana: entity.unit.max_power1
      })

    {holders, events} =
      Enum.reduce(holders, {holders, []}, fn %Holder{} = holder, {current_holders, events} ->
        incoming_spell_transition(current_holders, events, holder, owner_guid, attacker_guid, context)
      end)

    {entity, removal_events} = transition_holders(entity, holders, context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :kill,
        %{victim_guid: victim_guid} = context
      )
      when is_list(holders) and is_integer(victim_guid) do
    {holders, events} =
      Enum.reduce(holders, {holders, []}, fn %Holder{} = holder, {current_holders, events} ->
        kill_proc_transition(entity, current_holders, events, holder, owner_guid, context)
      end)

    {entity, removal_events} = transition_holders(entity, holders, context)
    {entity, events ++ removal_events}
  end

  def reactions(entity, _event, _context), do: {entity, []}

  defp incoming_spell_transition(holders, events, holder, owner_guid, attacker_guid, context) do
    %{spell: triggering_spell, proc_type: proc_type} = context

    proc? =
      not self_proc?(holder, triggering_spell) and proc_ready?(holder, Map.get(context, :now)) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, context) and Proc.roll?(holder.spell)

    if proc? do
      apply_incoming_spell_proc(holders, events, holder, owner_guid, attacker_guid, context)
    else
      {holders, events}
    end
  end

  defp apply_incoming_spell_proc(holders, events, holder, owner_guid, attacker_guid, context) do
    case Script.incoming_spell(holder, owner_guid, attacker_guid, context) do
      {:handled, updated_holder, proc_events} ->
        updated_holder = if updated_holder, do: mark_proc(updated_holder, Map.get(context, :now))
        {replace_or_delete(holders, holder, updated_holder), events ++ proc_events}

      :unhandled ->
        generic_incoming_spell_proc(holders, events, holder, owner_guid, attacker_guid, context)
    end
  end

  defp consume_reflection_charge(holders, events, %Holder{} = holder, %{outcome: :reflect, spell: spell, now: now}) do
    if reflects_school?(holder, Spell.school_mask(spell)) do
      {replace_or_delete(holders, holder, mark_proc(holder, now)), events}
    else
      {holders, events}
    end
  end

  defp consume_reflection_charge(holders, events, _holder, _context), do: {holders, events}

  defp generic_incoming_spell_proc(holders, events, %Holder{} = holder, owner_guid, attacker_guid, context) do
    case trigger_auras(holder) do
      [] ->
        consume_reflection_charge(holders, events, holder, context)

      proc_auras ->
        source_guid = holder.caster_guid || owner_guid

        proc_events =
          Enum.flat_map(proc_auras, &proc_events(&1, holder, source_guid, attacker_guid, context))

        {replace_or_delete(holders, holder, mark_proc(holder, Map.get(context, :now))), events ++ proc_events}
    end
  end

  defp reflects_school?(%Holder{auras: auras}, school_mask) do
    Enum.any?(auras, fn
      %Aura{type: :reflect_spells} ->
        true

      %Aura{type: :reflect_spells_school, misc_value: mask} when is_integer(mask) ->
        Bitwise.band(mask, school_mask) != 0

      _aura ->
        false
    end)
  end

  defp kill_proc_transition(entity, holders, events, holder, owner_guid, context) do
    modifier = &Modifiers.value(entity, holder.spell, :chance_of_success, &1)

    proc? =
      proc_ready?(holder, Map.get(context, :now)) and
        Proc.eligible?(holder.spell, nil, :kill, :normal) and Proc.roll?(holder.spell, nil, &:rand.uniform/0, modifier)

    if proc? do
      generic_outgoing_spell_proc(holders, events, holder, owner_guid, context)
    else
      {holders, events}
    end
  end

  defp outgoing_proc_transition(holders, events, holder, owner_guid, triggering_spell, proc_type, context) do
    proc? =
      not self_proc?(holder, triggering_spell) and proc_ready?(holder, Map.get(context, :now)) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, context) and Proc.roll?(holder.spell)

    if proc? do
      apply_outgoing_proc(holders, events, holder, owner_guid, context)
    else
      {holders, events}
    end
  end

  defp self_proc?(%Holder{spell: %Spell{id: id}}, %Spell{id: id}), do: true
  defp self_proc?(_holder, _triggering_spell), do: false

  defp apply_outgoing_proc(holders, events, holder, owner_guid, context) do
    case Script.outgoing_proc(holders, holder, owner_guid, context) do
      {:handled, updated_holders, proc_events} -> {updated_holders, events ++ proc_events}
      :unhandled -> generic_outgoing_spell_proc(holders, events, holder, owner_guid, context)
    end
  end

  @modifier_auras [:add_flat_modifier, :add_pct_modifier]

  defp generic_outgoing_spell_proc(holders, events, %Holder{} = holder, owner_guid, context) do
    victim_guid = Map.get(context, :victim_guid)

    proc_events =
      if is_integer(victim_guid) do
        Enum.flat_map(trigger_auras(holder), &proc_events(&1, holder, owner_guid, victim_guid, context)) ++
          ClassScript.events(holder, owner_guid, context) ++ HealingPower.events(holder, owner_guid, context)
      else
        []
      end

    cond do
      proc_events != [] ->
        {replace_or_delete(holders, holder, mark_proc(holder, Map.get(context, :now))), events ++ proc_events}

      spends_charge_without_trigger?(holder) ->
        {replace_or_delete(holders, holder, mark_proc(holder, Map.get(context, :now))), events}

      true ->
        {holders, events}
    end
  end

  defp spends_charge_without_trigger?(%Holder{charges: charges} = holder) do
    is_integer(charges) and not HealingPower.supported?(holder.spell) and
      not Holder.has_any_type?(holder, [:override_class_scripts | @modifier_auras])
  end

  defp trigger_auras(%Holder{auras: auras}) do
    Enum.filter(auras, fn
      %Aura{type: :proc_trigger_spell, trigger_spell_id: spell_id} when is_integer(spell_id) and spell_id > 0 -> true
      %Aura{type: :proc_trigger_damage, index: index} when is_integer(index) -> true
      _aura -> false
    end)
  end

  defp proc_events(%Aura{type: :proc_trigger_damage, index: index}, %Holder{spell: spell}, _source, target, _context) do
    [Effects.proc_damage(target, spell, index)]
  end

  defp proc_events(
         %Aura{type: :proc_trigger_spell, trigger_spell_id: spell_id},
         %Holder{} = holder,
         source,
         target,
         context
       ) do
    source
    |> Effects.trigger_spell(holder.caster_level || 1, target, spell_id, triggered_by_spell_id: holder.spell.id)
    |> ProcSpell.resolve(holder, context)
  end

  defp replace_or_delete(holders, holder, nil), do: List.delete(holders, holder)

  defp replace_or_delete(holders, holder, updated) do
    List.replace_at(holders, Enum.find_index(holders, &(&1 == holder)), updated)
  end

  defp transition_holders(entity, holders, context) do
    now = Map.get(context, :now, 0)
    Transition.run(entity, %Change{holders: holders, cause: :consumed, now: now})
  end

  defp incoming_reaction(
         entity,
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         triggering_spell,
         proc_type,
         outcome,
         context
       ) do
    context = Map.merge(context, %{spell: triggering_spell, proc_type: proc_type, outcome: outcome})

    case Script.incoming_melee(entity, holder, owner_guid, attacker_guid, context) do
      {:handled, updated_holder, events} ->
        {updated_holder, events}

      :unhandled ->
        generic_incoming_reaction(holder, owner_guid, attacker_guid, context)
    end
  end

  defp generic_incoming_reaction(%Holder{} = holder, owner_guid, attacker_guid, context) do
    %{spell: triggering_spell, proc_type: proc_type} = context
    now = Map.get(context, :now, 0)

    proc? =
      Holder.has_any_type?(holder, @charge_consuming_on_hit) and proc_ready?(holder, now) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, context) and Proc.roll?(holder.spell)

    shield? = proc_ready?(holder, now) and Proc.shield_outcome_allowed?(holder.spell, context)

    events =
      Enum.flat_map(holder.auras, &reaction_event(&1, holder, owner_guid, attacker_guid, proc?, shield?, context))

    {if(proc?, do: mark_proc(holder, now), else: holder), events}
  end

  defp outgoing_melee_reaction(%Holder{} = holder, owner_guid, victim_guid, context) do
    if weapon_allowed?(holder.spell, context) and extra_attack_allowed?(holder.spell, context) do
      {holder, events} =
        case Script.outgoing_melee(holder, owner_guid, victim_guid, context) do
          {:handled, updated_holder, events} -> {updated_holder, events}
          :unhandled -> generic_outgoing_melee_reaction(holder, owner_guid, victim_guid, context)
        end

      {holder, Enum.map(events, &melee_proc_origin(&1, context))}
    else
      {holder, []}
    end
  end

  defp extra_attack_allowed?(%Spell{spell_icon: 108, spell_visual: 2759}, %{extra_attack?: true}), do: false
  defp extra_attack_allowed?(_spell, _context), do: true

  defp weapon_allowed?(%Spell{equipped_item_class: class}, _context) when class in [nil, -1], do: true
  defp weapon_allowed?(%Spell{} = spell, %{weapon: weapon}), do: WeaponDamage.fits?(weapon, spell)
  defp weapon_allowed?(_spell, _context), do: true

  defp melee_proc_origin(%Effects.TriggerSpell{} = effect, context),
    do: %{effect | extra_attack?: Map.get(context, :extra_attack?, false), attack_hand: Map.get(context, :attack_hand)}

  defp melee_proc_origin(effect, _context), do: effect

  defp generic_outgoing_melee_reaction(
         %Holder{} = holder,
         owner_guid,
         victim_guid,
         %{proc_type: proc_type, now: now} = context
       ) do
    proc_auras = trigger_auras(holder)

    proc? =
      proc_auras != [] and proc_ready?(holder, now) and
        Proc.eligible?(holder.spell, Map.get(context, :spell), proc_type, context) and
        Proc.roll?(holder.spell, Map.get(context, :attack_time_ms))

    if proc? do
      events =
        Enum.flat_map(proc_auras, &proc_events(&1, holder, owner_guid, victim_guid, context))

      {mark_proc(holder, now), events}
    else
      {holder, []}
    end
  end

  defp proc_ready?(%Holder{next_proc_at: next_proc_at}, now) when is_integer(next_proc_at), do: now >= next_proc_at
  defp proc_ready?(%Holder{}, _now), do: true

  defp mark_proc(%Holder{charges: charges}, _now) when is_integer(charges) and charges <= 1, do: nil

  defp mark_proc(%Holder{} = holder, now) do
    cooldown_ms =
      case holder.spell.proc_rule do
        %{cooldown_ms: cooldown_ms} when is_integer(cooldown_ms) and cooldown_ms > 0 -> cooldown_ms
        _rule -> 0
      end

    charges = if is_integer(holder.charges), do: holder.charges - 1, else: holder.charges
    next_proc_at = if cooldown_ms > 0, do: now + cooldown_ms
    %{holder | charges: charges, next_proc_at: next_proc_at}
  end

  defp reaction_event(
         %Aura{type: :proc_trigger_damage} = aura,
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         true,
         _shield?,
         context
       ) do
    proc_events(aura, holder, owner_guid, attacker_guid, context)
  end

  defp reaction_event(
         %Aura{type: :damage_shield, trigger_spell_id: spell_id},
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         _proc?,
         shield?,
         context
       )
       when is_integer(spell_id) and spell_id > 0 do
    if shield?, do: trigger_reaction_events(holder, spell_id, owner_guid, attacker_guid, context), else: []
  end

  defp reaction_event(
         %Aura{type: :proc_trigger_spell, trigger_spell_id: spell_id},
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         proc?,
         _shield?,
         context
       )
       when is_integer(spell_id) and spell_id > 0 do
    if proc?, do: trigger_reaction_events(holder, spell_id, owner_guid, attacker_guid, context), else: []
  end

  defp reaction_event(
         %Aura{type: :damage_shield, amount: amount},
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         _proc?,
         shield?,
         _context
       )
       when shield? and is_integer(amount) and amount > 0 do
    spell = %{
      holder.spell
      | effects: [%Effect{index: 0, type: :school_damage, base_points: amount, implicit_target_a: :target_enemy}]
    }

    context = %CastContext{
      caster_guid: owner_guid,
      caster_level: holder.caster_level || 1,
      spell: spell,
      proc_damage?: true
    }

    [Effects.deliver_spell(attacker_guid, context, spell)]
  end

  defp reaction_event(_aura, _holder, _owner_guid, _attacker_guid, _proc?, _shield?, _context), do: []

  defp trigger_reaction_events(%Holder{} = holder, spell_id, owner_guid, attacker_guid, context) do
    aura_owner_guid = holder.caster_guid || owner_guid

    {source_guid, target_guid, trigger_spell_id} =
      Scripts.incoming_proc_trigger(holder.spell, spell_id, aura_owner_guid, attacker_guid)

    if is_integer(trigger_spell_id) do
      source_guid
      |> Effects.trigger_spell(holder.caster_level || 1, target_guid, trigger_spell_id,
        triggered_by_spell_id: holder.spell.id,
        hit_context: holder.cast_context
      )
      |> ProcSpell.resolve(holder, context)
    else
      []
    end
  end
end
