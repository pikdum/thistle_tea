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

  @unit_flag_possessed 0x01000000

  def sync(%Mob{object: %{guid: guid}, unit: %Unit{} = unit, internal: %Internal{} = internal} = mob) do
    possession = possession_holder(unit.auras)
    charm = charm_holder(unit.auras)

    cond do
      match?(%Holder{}, possession) -> sync_possession(mob, possession, internal.pet, guid)
      match?(%Pet{possessed?: true}, internal.pet) -> release_possession(mob, internal.pet)
      match?(%Holder{}, charm) -> sync_charm(mob, charm, internal.pet, guid)
      match?(%Pet{kind: :charmed}, internal.pet) -> release_charm(mob, internal.pet)
      true -> {mob, []}
    end
  end

  def sync(entity), do: {entity, []}

  defp sync_charm(%Mob{} = mob, %Holder{caster_guid: owner_guid}, %Pet{kind: :charmed, owner_guid: owner_guid}, _guid),
    do: {mob, []}

  defp sync_charm(%Mob{} = mob, %Holder{} = holder, %Pet{kind: :charmed} = previous, guid) do
    grant_charm(mob, holder, previous, [Event.control_released(previous.owner_guid, guid)])
  end

  defp sync_charm(%Mob{} = mob, %Holder{} = holder, nil, _guid), do: grant_charm(mob, holder, nil, [])
  defp sync_charm(%Mob{} = mob, _holder, _pet, _guid), do: {mob, []}

  defp grant_charm(%Mob{} = mob, %Holder{} = holder, previous, events) do
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

  defp release_charm(%Mob{} = mob, %Pet{} = pet) do
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

  defp sync_possession(
         %Mob{} = mob,
         %Holder{caster_guid: owner_guid},
         %Pet{possessed?: true, owner_guid: owner_guid},
         _guid
       ), do: {mob, []}

  defp sync_possession(%Mob{} = mob, %Holder{} = holder, previous, guid) do
    events =
      case previous do
        %Pet{kind: :charmed, owner_guid: owner_guid} -> [Event.control_released(owner_guid, guid)]
        _pet -> []
      end

    grant_possession(mob, holder, previous, events)
  end

  defp grant_possession(%Mob{} = mob, %Holder{} = holder, previous, events) do
    original_faction = original_value(previous, :original_faction_template, mob.unit.faction_template)
    original_npc_flags = original_value(previous, :original_npc_flags, mob.unit.npc_flags)

    pet = possession_pet(previous, holder, original_faction, original_npc_flags, mob.unit.flags || 0)
    faction_template = holder.caster_faction_template || mob.unit.faction_template

    mob = %{
      mob
      | unit: %{
          mob.unit
          | charmed_by: holder.caster_guid,
            faction_template: faction_template,
            npc_flags: 0,
            flags: Bitwise.bor(mob.unit.flags || 0, @unit_flag_possessed),
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

    spells = controlled_spells(mob)
    event = Event.control_granted(holder.caster_guid, mob.object.guid, holder.spell.id, spells, possess?: true)
    {Core.mark_broadcast_update(mob), events ++ [event]}
  end

  defp possession_pet(%Pet{} = pet, %Holder{} = holder, original_faction, original_npc_flags, original_unit_flags) do
    %{
      pet
      | owner_guid: holder.caster_guid,
        control_spell_id: holder.spell.id,
        original_faction_template: original_faction,
        original_npc_flags: original_npc_flags,
        possession_original_kind: pet.kind,
        possession_original_owner_guid: pet.owner_guid,
        possession_original_control_spell_id: pet.control_spell_id,
        possession_original_unit_flags: original_unit_flags,
        possession_original_command_state: pet.command_state,
        possession_original_reaction_state: pet.reaction_state,
        possessed?: true,
        command_state: :stay,
        reaction_state: :passive
    }
  end

  defp possession_pet(nil, %Holder{} = holder, original_faction, original_npc_flags, original_unit_flags) do
    %Pet{
      owner_guid: holder.caster_guid,
      profile: :combat,
      kind: :possessed,
      food_mask: 0,
      control_spell_id: holder.spell.id,
      original_faction_template: original_faction,
      original_npc_flags: original_npc_flags,
      possession_original_unit_flags: original_unit_flags,
      possessed?: true,
      command_state: :stay,
      reaction_state: :passive
    }
  end

  defp release_possession(%Mob{} = mob, %Pet{possession_original_kind: nil} = pet) do
    mob = restore_controlled_unit(mob, pet, nil)
    {mob, [Event.control_released(pet.owner_guid, mob.object.guid)]}
  end

  defp release_possession(%Mob{} = mob, %Pet{} = pet) do
    restored = %{
      pet
      | kind: pet.possession_original_kind,
        owner_guid: pet.possession_original_owner_guid,
        control_spell_id: pet.possession_original_control_spell_id,
        command_state: pet.possession_original_command_state || :follow,
        reaction_state: pet.possession_original_reaction_state || :defensive,
        possession_original_kind: nil,
        possession_original_owner_guid: nil,
        possession_original_control_spell_id: nil,
        possession_original_unit_flags: nil,
        possession_original_command_state: nil,
        possession_original_reaction_state: nil,
        possessed?: false
    }

    mob = restore_controlled_unit(mob, pet, restored)
    {mob, [Event.control_released(pet.owner_guid, mob.object.guid)]}
  end

  defp restore_controlled_unit(%Mob{} = mob, %Pet{} = pet, restored_pet) do
    mob = %{
      mob
      | unit: %{
          mob.unit
          | charmed_by: 0,
            faction_template: pet.original_faction_template,
            npc_flags: pet.original_npc_flags,
            flags: pet.possession_original_unit_flags || 0
        },
        internal: %{mob.internal | pet: restored_pet}
    }

    Core.mark_broadcast_update(mob)
  end

  defp controlled_spells(%Mob{} = mob) do
    (mob.internal.spellbook || %{}) |> Map.values() |> Enum.reject(&Spell.attribute?(&1, :passive))
  end

  defp possession_holder(holders) when is_list(holders) do
    Enum.find(holders, &Holder.has_any_type?(&1, [:mod_possess, :mod_possess_pet]))
  end

  defp possession_holder(_holders), do: nil

  defp charm_holder(holders) when is_list(holders), do: Enum.find(holders, &Holder.has_aura_type?(&1, :mod_charm))
  defp charm_holder(_holders), do: nil

  defp original_value(%Pet{} = pet, field, fallback), do: Map.get(pet, field) || fallback
  defp original_value(_pet, _field, fallback), do: fallback
end
