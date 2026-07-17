defmodule ThistleTea.Game.Entity.Logic.Aura.ControlSync do
  @moduledoc """
  Derives mob charm ownership from active control auras and emits ownership
  transition events for the controlling player's boundary.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  def sync(%Mob{object: %{guid: guid}, unit: %Unit{} = unit, internal: %Internal{} = internal} = mob) do
    holder = control_holder(unit.auras)

    case {holder, internal.pet} do
      {%Holder{caster_guid: owner_guid}, %Pet{kind: :charmed, owner_guid: owner_guid}} ->
        {mob, []}

      {%Holder{} = control, %Pet{kind: :charmed} = previous} ->
        grant_control(mob, control, previous, [Event.control_released(previous.owner_guid, guid)])

      {%Holder{} = control, nil} ->
        grant_control(mob, control, nil, [])

      {nil, %Pet{kind: :charmed} = pet} ->
        release_control(mob, pet)

      _ ->
        {mob, []}
    end
  end

  def sync(entity), do: {entity, []}

  defp grant_control(%Mob{} = mob, %Holder{} = holder, previous, events) do
    original_faction = original_value(previous, :original_faction_template, mob.unit.faction_template)
    original_npc_flags = original_value(previous, :original_npc_flags, mob.unit.npc_flags)

    pet = %Pet{
      owner_guid: holder.caster_guid,
      profile: :combat,
      kind: :charmed,
      food_mask: 0,
      control_spell_id: holder.spell.id,
      original_faction_template: original_faction,
      original_npc_flags: original_npc_flags
    }

    faction_template = holder.caster_faction_template || mob.unit.faction_template

    mob = %{
      mob
      | unit: %{
          mob.unit
          | charmed_by: holder.caster_guid,
            faction_template: faction_template,
            npc_flags: 0,
            target: 0
        },
        internal: %{
          mob.internal
          | pet: pet,
            in_combat: false,
            threat: %{},
            running: true
        }
    }

    spells = (mob.internal.spellbook || %{}) |> Map.values() |> Enum.reject(&Spell.attribute?(&1, :passive))
    event = Event.control_granted(holder.caster_guid, mob.object.guid, holder.spell.id, spells)
    {Core.mark_broadcast_update(mob), events ++ [event]}
  end

  defp release_control(%Mob{} = mob, %Pet{} = pet) do
    mob = %{
      mob
      | unit: %{
          mob.unit
          | charmed_by: 0,
            faction_template: pet.original_faction_template,
            npc_flags: pet.original_npc_flags
        },
        internal: %{mob.internal | pet: nil}
    }

    {Core.mark_broadcast_update(mob), [Event.control_released(pet.owner_guid, mob.object.guid)]}
  end

  defp control_holder(holders) when is_list(holders) do
    Enum.find(holders, &Holder.has_any_type?(&1, [:mod_charm, :mod_possess]))
  end

  defp control_holder(_holders), do: nil

  defp original_value(%Pet{} = pet, field, fallback), do: Map.get(pet, field) || fallback
  defp original_value(_pet, _field, fallback), do: fallback
end
