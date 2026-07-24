defmodule ThistleTea.Game.Entity.Logic.Aura.Script do
  @moduledoc """
  Interprets aura behavior that VMangos handles in spell scripts or explicit
  core spell-id branches because the spell data cannot express it.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.Priest
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Proc

  @wyvern_sting_poison_by_rank %{19_386 => 24_131, 24_132 => 24_134, 24_133 => 24_135}
  @combustion_proc_aura 11_129
  @sweeping_strikes [12_292, 18_765]
  @sweeping_strikes_damage 12_723
  @sweeping_strikes_loop_spells [12_723, 26_654]
  @retaliation 20_230
  @retaliation_strike 22_858
  @whirlwind 1680
  @melee_radius 5.0
  @whirlwind_radius 8.0

  def after_remove(entity, holders) when is_list(holders) do
    Enum.flat_map(holders, &after_remove_holder(entity, &1))
  end

  def outgoing_proc(holders, %Holder{spell: %Spell{} = spell} = holder, owner_guid, context)
      when is_list(holders) and is_integer(owner_guid) do
    if Spell.vmangos_script?(spell, "spell_mage_combustion_proc") do
      combustion_proc(holders, holder, owner_guid, context)
    else
      :unhandled
    end
  end

  def outgoing_proc(_holders, _holder, _owner_guid, _context), do: :unhandled

  def outgoing_melee(%Holder{spell: %Spell{id: id}} = holder, owner_guid, victim_guid, context)
      when id in @sweeping_strikes and is_integer(owner_guid) and is_integer(victim_guid) do
    damage = Map.get(context, :proc_damage, Map.get(context, :damage, 0))
    triggering_spell_id = Map.get(context, :triggering_spell_id)
    triggering_spell = Map.get(context, :spell)
    proc_type = Map.get(context, :proc_type)
    outcome = Map.get(context, :outcome)

    proc? =
      is_integer(damage) and damage > 1 and triggering_spell_id not in @sweeping_strikes_loop_spells and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and Proc.roll?(holder.spell)

    if proc? do
      radius = if triggering_spell_id == @whirlwind, do: @whirlwind_radius, else: @melee_radius
      event = Event.secondary_melee(victim_guid, damage, @sweeping_strikes_damage, radius)
      {:handled, spend_charge(holder), [event]}
    else
      {:handled, holder, []}
    end
  end

  def outgoing_melee(_holder, _owner_guid, _victim_guid, _context), do: :unhandled

  def incoming_melee(entity, %Holder{spell: %Spell{id: @retaliation}} = holder, owner_guid, attacker_guid, context)
      when is_integer(owner_guid) and is_integer(attacker_guid) do
    triggering_spell = Map.get(context, :spell)
    proc_type = Map.get(context, :proc_type)
    outcome = Map.get(context, :outcome)

    proc? =
      attacker_in_front?(entity, Map.get(context, :attacker_position)) and not stunned?(entity) and
        Proc.eligible?(holder.spell, triggering_spell, proc_type, outcome) and Proc.roll?(holder.spell)

    if proc? do
      event = Event.trigger_spell(owner_guid, holder.caster_level || 1, attacker_guid, @retaliation_strike)
      {:handled, spend_charge(holder), [event]}
    else
      {:handled, holder, []}
    end
  end

  def incoming_melee(_entity, _holder, _owner_guid, _attacker_guid, _context), do: :unhandled

  def incoming_spell(%Holder{spell: %Spell{} = spell} = holder, owner_guid, attacker_guid, context) do
    cond do
      Priest.vampiric_embrace?(spell) -> vampiric_embrace_proc(holder, attacker_guid, context)
      Paladin.eye_for_an_eye?(spell) -> eye_for_an_eye_proc(holder, owner_guid, attacker_guid, context)
      true -> :unhandled
    end
  end

  def incoming_spell(_holder, _owner_guid, _attacker_guid, _context), do: :unhandled

  defp vampiric_embrace_proc(%Holder{caster_guid: caster_guid} = holder, attacker_guid, %{damage: damage})
       when is_integer(caster_guid) and caster_guid == attacker_guid and is_integer(damage) and damage > 0 do
    heal = max(div(damage * dummy_amount(holder, 20), 100), 1)

    event =
      Event.trigger_spell(caster_guid, holder.caster_level || 1, caster_guid, Priest.vampiric_embrace_heal_id(),
        base_points: heal,
        effect_index: 0,
        resolve_targets?: true,
        triggered_by_spell_id: holder.spell.id
      )

    {:handled, holder, [event]}
  end

  defp vampiric_embrace_proc(holder, _attacker_guid, _context), do: {:handled, holder, []}

  defp eye_for_an_eye_proc(%Holder{} = holder, owner_guid, attacker_guid, %{damage: damage} = context)
       when is_integer(damage) and damage > 0 do
    max_health = Map.get(context, :owner_max_health) || 0
    reflected = damage |> Kernel.*(dummy_amount(holder, 0)) |> div(100) |> min(div(max_health, 2))

    if reflected > 0 do
      event =
        Event.trigger_spell(owner_guid, holder.caster_level || 1, attacker_guid, Paladin.eye_for_an_eye_damage_id(),
          base_points: reflected,
          effect_index: 0,
          triggered_by_spell_id: holder.spell.id
        )

      {:handled, holder, [event]}
    else
      {:handled, holder, []}
    end
  end

  defp eye_for_an_eye_proc(holder, _owner_guid, _attacker_guid, _context), do: {:handled, holder, []}

  defp dummy_amount(%Holder{auras: auras}, default) do
    Enum.find_value(auras, default, fn
      %{type: :dummy, amount: amount} when is_integer(amount) and amount > 0 -> amount
      _aura -> nil
    end)
  end

  def cancel_linked_spell_ids(%Holder{spell: %Spell{} = spell}) do
    if Spell.vmangos_script?(spell, "spell_mage_combustion_buff"), do: [@combustion_proc_aura], else: []
  end

  def cancel_linked_spell_ids(_holder), do: []

  defp after_remove_holder(%{object: %{guid: target_guid}}, %Holder{
         spell: %Spell{id: spell_id} = spell,
         caster_guid: caster_guid,
         caster_level: caster_level
       })
       when is_integer(caster_guid) and is_integer(target_guid) do
    case {spell.script_name, @wyvern_sting_poison_by_rank[spell_id]} do
      {"spell_hunter_wyvern_sting", poison_id} when is_integer(poison_id) ->
        [Event.trigger_spell(caster_guid, caster_level, target_guid, poison_id)]

      _other ->
        []
    end
  end

  defp after_remove_holder(_entity, _holder), do: []

  defp combustion_proc(holders, %Holder{} = holder, owner_guid, %{outcome: outcome}) do
    with visible_id when is_integer(visible_id) <- combustion_visible_spell_id(holder.spell),
         %Holder{spell: %Spell{} = visible} <- Enum.find(holders, &match?(%Holder{spell: %Spell{id: ^visible_id}}, &1)),
         true <- Spell.vmangos_script?(visible, "spell_mage_combustion_buff") do
      combustion_transition(holders, holder, owner_guid, visible_id, outcome)
    else
      _missing_visible -> {:handled, List.delete(holders, holder), []}
    end
  end

  defp combustion_visible_spell_id(%Spell{effects: effects}) do
    Enum.find_value(effects, fn
      %{type: :trigger_spell, trigger_spell_id: spell_id} when is_integer(spell_id) and spell_id > 0 -> spell_id
      _effect -> nil
    end)
  end

  defp combustion_transition(holders, %Holder{charges: charges} = holder, _owner_guid, visible_id, :crit)
       when is_integer(charges) and charges <= 1 do
    kept = Enum.reject(holders, &(&1 == holder or match?(%Holder{spell: %Spell{id: ^visible_id}}, &1)))
    {:handled, kept, []}
  end

  defp combustion_transition(holders, %Holder{} = holder, owner_guid, visible_id, outcome) do
    updated_holder = if outcome == :crit, do: %{holder | charges: max((holder.charges || 1) - 1, 0)}, else: holder
    updated_holders = List.replace_at(holders, Enum.find_index(holders, &(&1 == holder)), updated_holder)
    event = Event.trigger_spell(owner_guid, holder.caster_level || 1, owner_guid, visible_id)
    {:handled, updated_holders, [event]}
  end

  defp spend_charge(%Holder{charges: charges}) when is_integer(charges) and charges <= 1, do: nil
  defp spend_charge(%Holder{charges: charges} = holder) when is_integer(charges), do: %{holder | charges: charges - 1}
  defp spend_charge(%Holder{} = holder), do: holder

  defp attacker_in_front?(%{movement_block: %{position: {x, y, _z, orientation}}}, {ax, ay, _az}) do
    not Math.behind?({x, y, orientation}, {ax, ay})
  end

  defp attacker_in_front?(_entity, _attacker_position), do: true

  defp stunned?(%{unit: %{auras: holders}}) when is_list(holders) do
    Enum.any?(holders, &Holder.has_aura_type?(&1, :mod_stun))
  end

  defp stunned?(_entity), do: false
end
