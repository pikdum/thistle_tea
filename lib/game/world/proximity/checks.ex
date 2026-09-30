defmodule ThistleTea.Game.World.Proximity.Checks do
  @moduledoc """
  Owner-local delayed contacts, with one timer per announcer and role.
  References reject cancelled messages and identities reject old incarnations.
  """

  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.World.Entity

  def schedule(%{internal: %Internal{} = internal} = listener, %Announcement{guid: guid} = announcement, role, at, now) do
    key = {guid, role}
    identity = {announcement.world, Entity.pid(guid), announcement.path}

    case Map.get(internal.proximity_checks, key) do
      {_ref, ^identity, previous_at} when abs(previous_at - at) <= 1 ->
        listener

      _ ->
        listener = cancel(listener, guid, role)
        ref = :erlang.start_timer(max(at - now, 0), self(), {:proximity_due, guid, role})
        put(listener, key, {ref, identity, at})
    end
  end

  def take(%{internal: %Internal{} = internal} = listener, guid, role, ref) do
    case Map.get(internal.proximity_checks, {guid, role}) do
      {^ref, {world, pid, _path}, _at} ->
        listener = cancel(listener, guid, role)
        {listener, world == internal.world and pid == Entity.pid(guid)}

      _ ->
        {listener, false}
    end
  end

  def cancel(%{internal: %Internal{} = internal} = listener, guid, role) do
    case Map.pop(internal.proximity_checks, {guid, role}) do
      {nil, _checks} ->
        listener

      {{ref, _identity, _at}, checks} ->
        :erlang.cancel_timer(ref)
        %{listener | internal: %{internal | proximity_checks: checks}}
    end
  end

  def clear(%{internal: %Internal{} = internal} = listener) do
    Enum.each(internal.proximity_checks, fn {_key, {ref, _identity, _at}} -> :erlang.cancel_timer(ref) end)
    if internal.proximity_refresh, do: :erlang.cancel_timer(elem(internal.proximity_refresh, 0))
    %{listener | internal: %{internal | proximity_checks: %{}, proximity_refresh: nil}}
  end

  defp put(%{internal: %Internal{} = internal} = listener, key, check),
    do: %{listener | internal: %{internal | proximity_checks: Map.put(internal.proximity_checks, key, check)}}
end
