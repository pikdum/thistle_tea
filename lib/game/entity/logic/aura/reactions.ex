defmodule ThistleTea.Game.Entity.Logic.Aura.Reactions do
  @moduledoc """
  On-hit aura reactions: damage shields and proc triggers fire back at the
  attacker, and charge-limited holders spend a charge per hit taken.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Script
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
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
          incoming_reaction(holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome)

        {holder, events ++ holder_events}
      end)

    {sync_holders(entity, Enum.reject(holders, &is_nil/1)), events}
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

    {sync_holders(entity, holders), events}
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

  defp sync_holders(%{unit: %Unit{auras: current}} = entity, current), do: entity

  defp sync_holders(%{unit: %Unit{} = unit} = entity, holders) do
    %{entity | unit: UnitSync.sync_unit(%{unit | auras: holders})}
    |> Core.mark_broadcast_update()
  end

  defp spend_hit_charge(%Holder{charges: charges} = holder) when is_integer(charges) do
    cond do
      not Holder.has_any_type?(holder, @charge_consuming_on_hit) -> holder
      charges > 1 -> %{holder | charges: charges - 1}
      true -> nil
    end
  end

  defp spend_hit_charge(holder), do: holder

  defp incoming_reaction(%Holder{} = holder, owner_guid, attacker_guid, triggering_spell, proc_type, outcome) do
    proc? =
      Holder.has_any_type?(holder, @charge_consuming_on_hit) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and Proc.roll?(holder.spell)

    events = Enum.flat_map(holder.auras, &reaction_event(&1, holder, owner_guid, attacker_guid, proc?))
    {if(proc?, do: spend_hit_charge(holder), else: holder), events}
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
