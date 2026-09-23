defmodule ThistleTea.Game.Instance.Admission.Policy do
  @moduledoc false
  defstruct [:player_limit, raid?: false]
end

defmodule ThistleTea.Game.Instance.Admission.Actor do
  @moduledoc false
  @enforce_keys [:guid, :account]
  defstruct [:guid, :account, raid?: false]
end

defmodule ThistleTea.Game.Instance.Admission do
  @moduledoc "Pure raid-group, copy-capacity, and account-wide rolling instance entry rules."

  alias ThistleTea.Game.Instance.Admission.Actor
  alias ThistleTea.Game.Instance.Admission.Policy
  alias ThistleTea.Game.Instance.Copy
  alias ThistleTea.Game.WorldRef

  @hour_ms 3_600_000
  @entry_limit 5

  def check(history, %Policy{} = policy, %Actor{} = actor, %Copy{} = copy, now) do
    cond do
      copy.expired? -> {:error, :instance_unavailable}
      policy.raid? and not actor.raid? -> {:error, :raid_group_required}
      full?(copy, actor.guid, policy.player_limit) -> {:error, :instance_full}
      limited?(history, actor.account, copy.world, now) -> {:error, :too_many_instances}
      true -> :ok
    end
  end

  def record(history, %Actor{account: account}, %WorldRef{} = world, now) do
    entries = history |> Map.get(account, %{}) |> prune_entries(now) |> Map.put(world, now)
    Map.put(history, account, entries)
  end

  def prune(history, now) do
    history
    |> Map.new(fn {account, entries} -> {account, prune_entries(entries, now)} end)
    |> Map.reject(fn {_account, entries} -> map_size(entries) == 0 end)
  end

  defp full?(%Copy{members: members}, guid, limit) when is_integer(limit) and limit > 0 do
    not MapSet.member?(members, guid) and MapSet.size(members) >= limit
  end

  defp full?(_copy, _guid, _limit), do: false

  defp limited?(history, account, world, now) do
    entries = history |> Map.get(account, %{}) |> prune_entries(now)
    not Map.has_key?(entries, world) and map_size(entries) >= @entry_limit
  end

  defp prune_entries(entries, now), do: Map.reject(entries, fn {_world, entered_at} -> entered_at + @hour_ms < now end)
end
