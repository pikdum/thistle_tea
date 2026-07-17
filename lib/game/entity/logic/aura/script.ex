defmodule ThistleTea.Game.Entity.Logic.Aura.Script do
  @moduledoc """
  Interprets aura lifecycle behavior that VMangos marks with an explicit
  `spell_template.script_name` because the spell data cannot express it.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @wyvern_sting_poison_by_rank %{19_386 => 24_131, 24_132 => 24_134, 24_133 => 24_135}
  @combustion_proc_aura 11_129

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
end
