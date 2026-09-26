defmodule ThistleTea.Game.Entity.Logic.Guardians do
  @moduledoc """
  Owns the independent collection of autonomous summons for any unit caster.
  Direct player casts replace matching entries; triggered casts accumulate.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Effects

  def active(%{internal: %Internal{guardians: guardians}}), do: Map.values(guardians)

  def activate(%{internal: %Internal{} = internal} = entity, %EntityRef{guid: guid} = ref) do
    %{entity | internal: %{internal | guardians: Map.put(internal.guardians, guid, ref)}}
  end

  def removed(%{internal: %Internal{} = internal} = entity, guid) do
    %{entity | internal: %{internal | guardians: Map.delete(internal.guardians, guid)}}
  end

  def prepare(%Character{} = entity, %Effects.SummonGuardians{triggered?: false, entry: entry} = effect) do
    matching = Enum.filter(active(entity), &(&1.entry == entry))
    {dismiss(entity, matching), matching == [] or effect.replace?}
  end

  def prepare(entity, %Effects.SummonGuardians{entry: entry}) do
    {entity, match?(%Character{}, entity) or Enum.count(active(entity), &(&1.entry == entry)) < 16}
  end

  def dismiss_all(%{internal: %Internal{}} = entity), do: dismiss(entity, active(entity))
  def dismiss_all(entity), do: entity

  def dismiss_entry(%{internal: %Internal{}} = entity, entry) when is_integer(entry) and entry > 0 do
    dismiss(entity, Enum.filter(active(entity), &(&1.entry == entry)))
  end

  defp dismiss(entity, refs) do
    Enum.reduce(refs, entity, fn %EntityRef{guid: guid}, entity ->
      entity |> removed(guid) |> Effects.enqueue(%Effects.DespawnEntity{target_guid: guid})
    end)
  end
end
