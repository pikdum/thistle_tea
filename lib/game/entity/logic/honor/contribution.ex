defmodule ThistleTea.Game.Entity.Logic.Honor.Contribution do
  @moduledoc """
  Recent player damage and group honor shares. Nonplayer damage remains in
  the denominator, while only nearby living enemy players receive credit.
  Damage history expires after one minute without further damage.
  """

  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Honor.Participant

  @history_timeout_ms 60_000

  def record(%Damage{} = history, player_guid, damage, now) when is_number(damage) and damage > 0 and is_integer(now) do
    history = current(history, now)
    player_guid = if is_integer(player_guid) and player_guid > 0, do: player_guid, else: 0
    now = if is_integer(history.last_damage_at), do: max(now, history.last_damage_at), else: now

    %{history | by_player: Map.update(history.by_player, player_guid, damage, &(&1 + damage)), last_damage_at: now}
  end

  def record(%Damage{} = history, _player_guid, _damage, _now), do: history

  def current(%Damage{last_damage_at: previous} = history, now) when is_integer(previous) do
    if now - previous > @history_timeout_ms, do: %Damage{}, else: history
  end

  def current(%Damage{} = history, _now), do: history

  def shares(%Damage{} = history, participants, victim_team, now) do
    history = current(history, now)
    total = history.by_player |> Map.values() |> Enum.sum()

    if total > 0 do
      profiles = Map.new(participants, &{&1.guid, &1})

      history.by_player
      |> damage_groups(profiles)
      |> Enum.flat_map(&group_shares(&1, participants, victim_team, total))
      |> Map.new()
    else
      %{}
    end
  end

  defp damage_groups(damage, profiles) do
    Enum.reduce(damage, %{}, fn {guid, damage}, groups ->
      case Map.get(profiles, guid) do
        %Participant{group_id: group} when not is_nil(group) ->
          Map.update(groups, {:group, group}, damage, &(&1 + damage))

        %Participant{} ->
          Map.put(groups, {:player, guid}, damage)

        nil ->
          groups
      end
    end)
  end

  defp group_shares({key, damage}, participants, victim_team, total) do
    rewarded = Enum.filter(participants, &(eligible?(&1, victim_team) and member?(&1, key)))
    count = length(rewarded)
    multiplier = group_rate(count)

    Enum.map(rewarded, fn %Participant{guid: guid} -> {guid, damage / total * multiplier / count} end)
  end

  defp eligible?(%Participant{alive?: true, in_range?: true, team: team}, victim_team) do
    team in [:alliance, :horde] and team != victim_team
  end

  defp eligible?(%Participant{}, _victim_team), do: false

  defp member?(%Participant{guid: guid}, {:player, guid}), do: true
  defp member?(%Participant{group_id: group}, {:group, group}), do: true
  defp member?(%Participant{}, _key), do: false

  defp group_rate(count) when count <= 2, do: 1.0
  defp group_rate(3), do: 1.166
  defp group_rate(4), do: 1.3
  defp group_rate(5), do: 1.4
  defp group_rate(count), do: max(1 - count * 0.05, 0.01)
end
