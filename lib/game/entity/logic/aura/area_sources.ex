defmodule ThistleTea.Game.Entity.Logic.Aura.AreaSources do
  @moduledoc """
  Combines independently delivered ground effects in one spell holder and removes
  each effect with its own source. Overlapping sources share an existing effect
  until it ends; refreshes preserve its magnitude and periodic schedule.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.PersistentArea
  alias ThistleTea.Game.Spell.PersistentArea.Check

  def merge(%Holder{} = current, %Holder{} = incoming) do
    if ground?(current) and ground?(incoming) do
      auras = Enum.uniq_by(current.auras ++ incoming.auras, & &1.index)
      effects = Enum.uniq_by(current.spell.effects ++ incoming.spell.effects, & &1.index)
      spell = %{current.spell | effects: Enum.sort_by(effects, & &1.index)}
      synchronize(%{current | spell: spell}, auras)
    else
      incoming
    end
  end

  def remove(holders, area_guid), do: reject(holders, &(&1.guid == area_guid))

  def expire(holders, now), do: reject(holders, &(&1.expires_at <= now))

  def retain_available(%Holder{} = holder, %CastContext{area_checks: checks}) do
    reject_holder(holder, &match?(%Check{available?: false}, Map.get(checks, &1.guid)))
  end

  def retain_available(%Holder{} = holder, _context), do: [holder]

  defp reject(holders, predicate), do: Enum.flat_map(holders, &reject_holder(&1, predicate))

  defp reject_holder(%Holder{} = holder, predicate) do
    auras =
      Enum.reject(holder.auras, fn
        %Aura{persistent_area: %PersistentArea{} = area} -> predicate.(area)
        _aura -> false
      end)

    cond do
      auras == holder.auras -> [holder]
      auras == [] -> []
      true -> [synchronize(holder, auras)]
    end
  end

  defp synchronize(%Holder{} = holder, auras) do
    indices = Enum.map(auras, & &1.index)
    spell = %{holder.spell | effects: Enum.filter(holder.spell.effects, &(&1.index in indices))}
    expires_at = Enum.max_by(auras, & &1.persistent_area.expires_at).persistent_area.expires_at
    context = %{holder.cast_context | spell: spell}
    %{holder | auras: Enum.sort_by(auras, & &1.index), spell: spell, cast_context: context, expires_at: expires_at}
  end

  defp ground?(%Holder{auras: auras}),
    do: auras != [] and Enum.all?(auras, &match?(%Aura{persistent_area: %PersistentArea{}}, &1))
end
