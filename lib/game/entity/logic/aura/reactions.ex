defmodule ThistleTea.Game.Entity.Logic.Aura.Reactions do
  @moduledoc """
  On-hit aura reactions: damage shields and proc triggers fire back at the
  attacker, and charge-limited holders spend a charge per hit taken.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event

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
      %{entity | unit: UnitSync.sync_unit(%{entity.unit | auras: new_holders})}
      |> Core.mark_broadcast_update()
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

  defp reaction_event(%Aura{type: type, trigger_spell_id: spell_id}, %Holder{} = holder, owner_guid, attacker_guid)
       when type in [:damage_shield, :proc_trigger_spell] and is_integer(spell_id) and spell_id > 0 do
    source_guid = holder.caster_guid || owner_guid
    source_level = holder.caster_level || 1
    [Event.trigger_spell(source_guid, source_level, attacker_guid, spell_id)]
  end

  defp reaction_event(_aura, _holder, _owner_guid, _attacker_guid), do: []
end
