defmodule ThistleTea.Game.Entity.Logic.DiminishingReturns do
  @moduledoc """
  Target-owned crowd-control history. Each successful aura application advances
  its group, including refreshes and casts from other sources. Recovery starts
  only when the last holder in that group leaves the aura transition funnel.
  """
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.DiminishingReturns, as: Groups

  defstruct applications: 0, reset_at: nil

  @recovery_ms 15_000

  def apply(entity, %Holder{negative?: true, applied_at: start, expires_at: finish} = holder, context, now)
      when is_integer(start) and is_integer(finish) and finish != -1 and finish > start do
    group = Groups.group(holder.spell, context.triggered_by_aura?)

    if applicable?(entity, context, group) do
      diminish(entity, holder, group, now)
    else
      {:ok, entity, holder}
    end
  end

  def apply(entity, holder, _context, _now), do: {:ok, entity, holder}

  def reconcile(%{internal: %Internal{} = internal} = entity, previous, current, now) do
    previous = active_groups(previous)
    current = active_groups(current)

    history =
      Map.new(internal.diminishing_returns, fn {group, entry} ->
        entry =
          cond do
            MapSet.member?(current, group) -> %{entry | reset_at: nil}
            MapSet.member?(previous, group) -> %{entry | reset_at: now + @recovery_ms}
            true -> entry
          end

        {group, entry}
      end)

    %{entity | internal: %{internal | diminishing_returns: history}}
  end

  def reconcile(entity, _previous, _current, _now), do: entity

  defp diminish(%{internal: %Internal{} = internal} = entity, holder, group, now) do
    entry = internal.diminishing_returns |> Map.get(group, %__MODULE__{}) |> recover(now)

    if entry.applications == 3 do
      {:immune, entity}
    else
      duration = div(holder.expires_at - holder.applied_at, Integer.pow(2, entry.applications))
      entry = %{entry | applications: entry.applications + 1, reset_at: nil}
      history = Map.put(internal.diminishing_returns, group, entry)
      entity = %{entity | internal: %{internal | diminishing_returns: history}}
      holder = %{holder | expires_at: holder.applied_at + duration, diminishing_group: group}
      {:ok, entity, holder}
    end
  end

  defp recover(%__MODULE__{reset_at: at}, now) when is_integer(at) and now >= at, do: %__MODULE__{}
  defp recover(entry, _now), do: entry

  defp active_groups(holders) do
    holders |> Enum.map(& &1.diminishing_group) |> Enum.reject(&is_nil/1) |> MapSet.new()
  end

  defp applicable?(entity, context, group) do
    case Groups.scope(group) do
      :all -> hostile?(entity, context)
      :pvp -> hostile?(entity, context) and player_controlled?(entity) and player_caster?(context)
      :none -> false
    end
  end

  defp hostile?(%{object: %{guid: guid}}, %CastContext{caster_guid: guid, reflected_by_guid: nil}), do: false
  defp hostile?(_entity, %CastContext{reflected_by_guid: guid}) when is_integer(guid), do: true
  defp hostile?(_entity, %CastContext{target_hostile?: false}), do: false
  defp hostile?(_entity, _context), do: true

  defp player_controlled?(%Character{}), do: true
  defp player_controlled?(%{internal: %Internal{pet: %{owner_guid: owner}}}) when is_integer(owner), do: true
  defp player_controlled?(_entity), do: false

  defp player_caster?(%CastContext{caster_type: :player}), do: true

  defp player_caster?(%CastContext{caster_guid: guid, caster_owner_guid: owner})
       when is_integer(owner) and owner != guid, do: true

  defp player_caster?(_context), do: false
end
