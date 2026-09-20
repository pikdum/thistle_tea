defmodule ThistleTea.Game.Entity.KillReward do
  @moduledoc """
  Resolves creature kill recipients from the original tap and current world
  presence. Experience, quest credit, and creature honor share this selection.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party

  def selection(%Mob{} = mob, source, opts \\ []) do
    group_of = Keyword.get(opts, :group_of, &Party.group_of/1)
    group = Keyword.get(opts, :group, &Party.group/1)
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid]))

    {player, group_id} =
      case mob.internal.loot do
        %{tapped_by: %Tap{player: player, group_id: group_id}} -> {player, group_id}
        _untapped -> {controlling_player(source, metadata), nil}
      end

    case group.(group_id) || group_of.(player) do
      %Group{} = group -> {:group, group}
      nil -> if is_integer(player) and player > 0 and Guid.entity_type(player) == :player, do: {:solo, player}
    end
  end

  def eligible_members(%Mob{} = mob, %Group{} = group, opts \\ []) do
    nearby = Keyword.get(opts, :nearby, &World.nearby_players/2)
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:level, :alive?]))
    members = MapSet.new(group.members, & &1.guid)

    mob
    |> nearby.(Experience.group_reward_distance())
    |> Enum.filter(fn {guid, _distance} -> MapSet.member?(members, guid) end)
    |> Enum.flat_map(fn {guid, _distance} ->
      case metadata.(guid) do
        %{level: level, alive?: true} when is_integer(level) -> [%{guid: guid, level: level}]
        _ineligible -> []
      end
    end)
  end

  defp controlling_player(guid, metadata) when is_integer(guid) and guid > 0 do
    if Guid.entity_type(guid) == :player do
      guid
    else
      case metadata.(guid) do
        %{owner_guid: owner} when is_integer(owner) and owner > 0 -> owner
        _unowned -> nil
      end
    end
  end

  defp controlling_player(_source, _metadata), do: nil
end
