defmodule ThistleTea.Game.Entity.Logic.Aura.TauntSync do
  @moduledoc """
  Matches temporary threat when forced-attack auras arrive and removes the
  borrowed amount when a caster's final taunt ends. Threat earned during the
  taunt remains on the table.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Threat

  def sync(%Mob{} = entity, previous, current) do
    previous = Enum.filter(previous, &Holder.has_aura_type?(&1, :mod_taunt))
    current = Enum.filter(current, &Holder.has_aura_type?(&1, :mod_taunt))
    remaining = MapSet.new(current, & &1.caster_guid)

    entity =
      previous
      |> Enum.map(& &1.caster_guid)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(remaining, &1))
      |> Enum.reduce(entity, &Threat.set_temporary(&2, &1, 0))

    applied = MapSet.new(previous, &{Holder.key(&1), &1.applied_at})

    current
    |> Enum.reject(&MapSet.member?(applied, {Holder.key(&1), &1.applied_at}))
    |> Enum.reduce(entity, &Threat.apply_taunt(&2, &1.caster_guid))
  end

  def sync(entity, _previous, _current), do: entity
end
