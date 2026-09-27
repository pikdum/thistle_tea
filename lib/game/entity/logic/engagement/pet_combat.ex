defmodule ThistleTea.Game.Entity.Logic.Engagement.PetCombat do
  @moduledoc """
  Pet combat participation independent of attack selection and movement commands.

  Incoming threat references hold PvE combat until their owning creatures release
  them. A short contact window covers PvP and attacks without a threat list.
  The entity owner supplies observations to prune references before regeneration.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatReferences
  alias ThistleTea.Game.Entity.Logic.CombatTimer
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid

  def contact(
        %Mob{object: %{guid: guid}, internal: %{pet: %Pet{}}, unit: %{health: health}} = entity,
        source,
        now,
        role,
        timed?
      )
      when is_number(health) and health > 0 and is_integer(source) and source > 0 and is_integer(now) do
    if source != guid and Guid.entity_type(source) in [:player, :mob, :pet] do
      entity =
        if role == :attack,
          do: CombatTimer.attack(entity, source, now, timed?),
          else: CombatTimer.attacked(entity, source, now)

      Combat.sync_combat_flag(entity)
    else
      entity
    end
  end

  def contact(entity, _source, _now, _role, _timed?), do: entity

  def gain_ref(%Mob{internal: %{pet: %Pet{}}, unit: %{health: health}} = entity, guid, incarnation)
      when is_number(health) and health > 0 and is_integer(guid) and guid > 0 and is_integer(incarnation) and
             incarnation > 0 do
    refs = MapSet.put(entity.internal.threat_refs || MapSet.new(), {guid, incarnation})
    entity |> put_refs(refs) |> set_combat(true)
  end

  def gain_ref(entity, _guid, _incarnation), do: entity

  def lose_ref(%Mob{internal: %{pet: %Pet{}, threat_refs: %MapSet{} = refs}} = entity, guid, incarnation) do
    put_refs(entity, MapSet.delete(refs, {guid, incarnation}))
  end

  def lose_ref(entity, _guid, _incarnation), do: entity

  def reconcile(%Mob{internal: %{pet: %Pet{}}} = entity, %Context{now: now, perception: perception}) do
    refs = CombatReferences.prune(entity.internal.threat_refs, entity.internal.world, perception)
    target = entity.unit.target
    attacking? = is_integer(target) and target > 0

    combat? =
      entity.unit.health > 0 and
        (attacking? or MapSet.size(refs) > 0 or CombatTimer.remaining(entity, now) > 0 or
           (entity.internal.in_combat == true and Aura.has_aura?(entity, :interrupt_regen)))

    entity |> put_refs(refs) |> set_combat(combat?)
  end

  def reconcile(entity, _context), do: entity

  def leave(%Mob{internal: %{pet: %Pet{}}} = entity, :pet_command) do
    pending? =
      is_integer(entity.internal.last_hostile_time) or MapSet.size(entity.internal.threat_refs || MapSet.new()) > 0

    set_combat(entity, entity.internal.in_combat == true and entity.unit.health > 0 and pending?)
  end

  def leave(%Mob{internal: %{pet: %Pet{}} = internal} = entity, _reason) do
    %{entity | internal: %{internal | threat_refs: MapSet.new()}}
  end

  def leave(entity, _reason), do: entity

  defp put_refs(%Mob{internal: %Internal{} = internal} = entity, refs) do
    if internal.threat_refs == refs do
      entity
    else
      %{entity | internal: %{internal | threat_refs: refs}} |> Core.mark_broadcast_update()
    end
  end

  defp set_combat(%Mob{internal: %Internal{} = internal} = entity, combat?) do
    %{entity | internal: %{internal | in_combat: combat?}} |> Combat.sync_combat_flag()
  end
end
