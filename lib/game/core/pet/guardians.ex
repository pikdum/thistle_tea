defmodule ThistleTea.Game.Core.Pet.Guardians do
  @moduledoc """
  Owns the independent collection of autonomous summons for any unit caster.
  Direct player casts replace matching entries; triggered casts accumulate.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Guardian
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Spell.Cooldowns

  def active(%{internal: %Internal{guardians: guardians}}), do: Map.values(guardians)

  def activate(%{internal: %Internal{} = internal} = entity, %EntityRef{guid: guid} = ref) do
    %{entity | internal: %{internal | guardians: Map.put(internal.guardians, guid, ref)}}
  end

  def removed(%{internal: %Internal{} = internal} = entity, guid, now) do
    {ref, guardians} = Map.pop(internal.guardians, guid)
    entity = %{entity | internal: %{internal | guardians: guardians}}
    release_cooldown(entity, ref, now)
  end

  def prepare(%Character{} = entity, %Effects.SummonGuardians{triggered?: false, entry: entry} = effect, now) do
    matching = Enum.filter(active(entity), &(&1.entry == entry))
    {dismiss(entity, matching, now), matching == [] or effect.replace?}
  end

  def prepare(entity, %Effects.SummonGuardians{entry: entry}, _now) do
    {entity, match?(%Character{}, entity) or Enum.count(active(entity), &(&1.entry == entry)) < 16}
  end

  def dismiss_all(%{internal: %Internal{}} = entity, now), do: dismiss(entity, active(entity), now)
  def dismiss_all(entity, _now), do: entity

  def dismiss_entry(%{internal: %Internal{}} = entity, entry, now) when is_integer(entry) and entry > 0 do
    dismiss(entity, Enum.filter(active(entity), &(&1.entry == entry)), now)
  end

  def on_death(%Mob{internal: %{guardian: %Guardian{cooldown_started_at: started_at}, pet: %Pet{}}} = entity)
      when is_integer(started_at) do
    effect = %Effects.ActivateCooldown{
      target_guid: entity.internal.pet.owner_guid,
      spell_id: entity.unit.created_by_spell,
      started_at: started_at
    }

    guardian = %{entity.internal.guardian | cooldown_started_at: nil}
    entity = %{entity | internal: %{entity.internal | guardian: guardian}}
    Effects.enqueue(entity, effect)
  end

  def on_death(entity), do: entity

  defp release_cooldown(entity, %EntityRef{spell_id: spell_id, cooldown_started_at: started_at}, now)
       when is_integer(started_at) do
    {entity, events} = Cooldowns.activate(entity, spell_id, now, started_at)
    Effects.enqueue(entity, events)
  end

  defp release_cooldown(entity, _ref, _now), do: entity

  defp dismiss(entity, refs, now) do
    Enum.reduce(refs, entity, fn %EntityRef{guid: guid}, entity ->
      entity |> removed(guid, now) |> Effects.enqueue(%Effects.DespawnEntity{target_guid: guid})
    end)
  end
end
