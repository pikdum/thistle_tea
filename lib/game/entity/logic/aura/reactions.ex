defmodule ThistleTea.Game.Entity.Logic.Aura.Reactions do
  @moduledoc """
  On-hit aura reactions: damage shields and proc triggers fire back at the
  attacker, and charge-limited holders spend a charge per hit taken.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.HolderSync
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.Scripts

  @charge_consuming_on_hit [:damage_shield, :proc_trigger_spell, :mod_resistance, :mod_resistance_exclusive]

  def reactions(entity, :hit_taken, %{attacker_guid: attacker_guid} = context)
      when is_integer(attacker_guid) and not is_map_key(context, :proc_type) do
    reactions(entity, :hit_taken, Map.merge(context, %{proc_type: :take_melee_swing, outcome: :normal}))
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :hit_taken,
        %{attacker_guid: attacker_guid, proc_type: proc_type, outcome: outcome} = context
      )
      when is_list(holders) and is_integer(attacker_guid) and proc_type in [:take_melee_swing, :take_melee_ability] and
             outcome in [:normal, :crit] do
    triggering_spell = Map.get(context, :spell)

    {holders, events} =
      Enum.map_reduce(holders, [], fn %Holder{} = holder, events ->
        {holder, holder_events} =
          incoming_reaction(entity, holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome, context)

        {holder, events ++ holder_events}
      end)

    {entity, removal_events} = sync_removals(entity, Enum.reject(holders, &is_nil/1), context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :spell_hit_dealt,
        %{spell: %Spell{} = triggering_spell, outcome: outcome, proc_type: proc_type} = context
      )
      when is_list(holders) and outcome in [:normal, :crit] and
             proc_type in [:deal_harmful_spell, :deal_harmful_periodic] do
    {holders, events} =
      Enum.reduce(holders, {holders, []}, fn %Holder{} = holder, {current_holders, events} ->
        outgoing_proc_transition(
          current_holders,
          events,
          holder,
          owner_guid,
          triggering_spell,
          proc_type,
          outcome,
          context
        )
      end)

    {entity, removal_events} = sync_removals(entity, holders, context)
    {entity, events ++ removal_events}
  end

  def reactions(
        %{object: %{guid: owner_guid}, unit: %Unit{auras: holders}} = entity,
        :melee_hit_dealt,
        %{victim_guid: victim_guid, outcome: outcome, proc_type: proc_type, now: now} = context
      )
      when is_list(holders) and is_integer(victim_guid) and outcome in [:normal, :crit] and
             proc_type in [:deal_melee_swing, :deal_melee_ability] and is_integer(now) do
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

    {entity, removal_events} = sync_removals(entity, Enum.reject(holders, &is_nil/1), context)
    {entity, events ++ removal_events}
  end

  def reactions(entity, _event, _context), do: {entity, []}

  defp outgoing_proc_transition(holders, events, holder, owner_guid, triggering_spell, proc_type, outcome, context) do
    if Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and Proc.roll?(holder.spell) do
      apply_outgoing_proc(holders, events, holder, owner_guid, context)
    else
      {holders, events}
    end
  end

  defp apply_outgoing_proc(holders, events, holder, owner_guid, context) do
    case Script.outgoing_proc(holders, holder, owner_guid, context) do
      {:handled, updated_holders, proc_events} -> {updated_holders, events ++ proc_events}
      :unhandled -> {holders, events}
    end
  end

  defp sync_holders(%{unit: %Unit{auras: current}} = entity, current), do: {entity, []}

  defp sync_holders(%{unit: %Unit{}} = entity, holders) do
    {entity, events} = HolderSync.sync(entity, holders)
    {Core.mark_broadcast_update(entity), events}
  end

  defp sync_removals(%{unit: %Unit{auras: previous}} = entity, holders, context) do
    removed = previous -- holders
    {entity, modifier_events} = sync_holders(entity, holders)

    case {removed, Map.get(context, :now)} do
      {[], _now} ->
        {entity, modifier_events}

      {removed, now} when is_integer(now) ->
        script_events = Script.after_remove(entity, removed)
        {entity, cooldown_events} = Cooldowns.activate_on_event(entity, removed, now)
        {entity, modifier_events ++ script_events ++ cooldown_events}

      {removed, _now} ->
        {entity, modifier_events ++ Script.after_remove(entity, removed)}
    end
  end

  defp spend_hit_charge(%Holder{charges: charges} = holder) when is_integer(charges) do
    cond do
      not Holder.has_any_type?(holder, @charge_consuming_on_hit) -> holder
      charges > 1 -> %{holder | charges: charges - 1}
      true -> nil
    end
  end

  defp spend_hit_charge(holder), do: holder

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
        generic_incoming_reaction(holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome)
    end
  end

  defp generic_incoming_reaction(%Holder{} = holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome) do
    proc? =
      Holder.has_any_type?(holder, @charge_consuming_on_hit) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and Proc.roll?(holder.spell)

    events = Enum.flat_map(holder.auras, &reaction_event(&1, holder, owner_guid, attacker_guid, proc?))
    {if(proc?, do: spend_hit_charge(holder), else: holder), events}
  end

  defp outgoing_melee_reaction(%Holder{} = holder, owner_guid, victim_guid, context) do
    triggering_spell = Map.get(context, :spell)
    proc_type = Map.fetch!(context, :proc_type)
    outcome = Map.fetch!(context, :outcome)
    attack_time_ms = Map.get(context, :attack_time_ms)
    now = Map.fetch!(context, :now)

    case Script.outgoing_melee(
           holder,
           owner_guid,
           victim_guid,
           context
         ) do
      {:handled, updated_holder, events} ->
        {updated_holder, events}

      :unhandled ->
        generic_outgoing_melee_reaction(
          holder,
          owner_guid,
          victim_guid,
          triggering_spell,
          proc_type,
          outcome,
          attack_time_ms,
          now
        )
    end
  end

  defp generic_outgoing_melee_reaction(
         %Holder{} = holder,
         owner_guid,
         victim_guid,
         triggering_spell,
         proc_type,
         outcome,
         attack_time_ms,
         now
       ) do
    proc_auras =
      Enum.filter(holder.auras, fn
        %Aura{type: :proc_trigger_spell, trigger_spell_id: spell_id} when is_integer(spell_id) and spell_id > 0 -> true
        _aura -> false
      end)

    proc? =
      proc_auras != [] and proc_ready?(holder, now) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and
        Proc.roll?(holder.spell, attack_time_ms)

    if proc? do
      events =
        Enum.map(proc_auras, fn %Aura{trigger_spell_id: spell_id} ->
          Event.trigger_spell(owner_guid, holder.caster_level || 1, victim_guid, spell_id,
            triggered_by_spell_id: holder.spell.id
          )
        end)

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
         %Aura{type: type, trigger_spell_id: spell_id},
         %Holder{} = holder,
         owner_guid,
         attacker_guid,
         proc?
       )
       when type in [:damage_shield, :proc_trigger_spell] and is_integer(spell_id) and spell_id > 0 do
    if type == :damage_shield or proc? do
      aura_owner_guid = holder.caster_guid || owner_guid
      source_level = holder.caster_level || 1

      {source_guid, target_guid, trigger_spell_id} =
        Scripts.incoming_proc_trigger(holder.spell, spell_id, aura_owner_guid, attacker_guid)

      if is_integer(trigger_spell_id) do
        [
          Event.trigger_spell(source_guid, source_level, target_guid, trigger_spell_id,
            triggered_by_spell_id: holder.spell.id
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  defp reaction_event(
         %Aura{type: :damage_shield, amount: amount},
         %Holder{} = holder,
         _owner_guid,
         attacker_guid,
         _proc?
       )
       when is_integer(amount) and amount > 0 do
    spell = %{
      holder.spell
      | school: :holy,
        effects: [%Effect{index: 0, type: :school_damage, base_points: amount, implicit_target_a: :target_enemy}]
    }

    context = %CastContext{caster_guid: holder.caster_guid, caster_level: holder.caster_level || 1, spell: spell}
    [Event.deliver_spell(attacker_guid, context, spell)]
  end

  defp reaction_event(_aura, _holder, _owner_guid, _attacker_guid, _proc?), do: []
end
