defmodule ThistleTea.Game.Entity.KillReward do
  @moduledoc """
  Resolves creature kill recipients from the original tap and current world
  presence. Experience, quest credit, and creature honor share this selection.
  """

  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.DamageOrigin
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.GroupReward
  alias ThistleTea.Game.Entity.Logic.GroupReward.Member
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party

  def selection(%Mob{} = mob, source, opts \\ []) do
    if DamageOrigin.loot_allowed?(mob) do
      tapped_selection(mob, source, opts)
    else
      metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid]))
      if guid = controlling_player(source, metadata), do: {:solo, guid}
    end
  end

  defp tapped_selection(%Mob{} = mob, source, opts) do
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
    members = group.members |> MapSet.new(& &1.guid) |> MapSet.put(original_tagger(mob))

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

  def group_rewards(%Mob{} = mob, %Group{} = group, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:level, :alive?, :ghost?]))
    position = Keyword.get(opts, :position, &World.position/1)
    tagger = original_tagger(mob)

    group.members
    |> Enum.map(& &1.guid)
    |> then(&Enum.uniq([tagger | &1]))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&group_member(mob, &1, tagger, metadata, position))
    |> GroupReward.plan(mob.unit.level, Experience.kill_options(mob))
  end

  defp original_tagger(%Mob{internal: %{loot: %{tapped_by: %Tap{player: guid}}}}), do: guid
  defp original_tagger(%Mob{}), do: nil

  defp group_member(mob, guid, tagger, metadata, position) do
    with %{level: level, alive?: alive?, ghost?: ghost?} when is_integer(level) and level > 0 <- metadata.(guid),
         location when not is_nil(location) <- position.(guid),
         true <- in_range?(mob, location) or (not alive? and in_range?(mob, position.(Corpse.guid_for(guid)))) do
      [%Member{guid: guid, level: level, alive?: alive?, ghost?: ghost?, original_tagger?: guid == tagger}]
    else
      _ineligible -> []
    end
  end

  def controlling_player(guid, metadata) when is_integer(guid) and guid > 0 do
    case player_owner(metadata.(guid)) do
      owner when is_integer(owner) -> owner
      nil -> if Guid.entity_type(guid) == :player, do: guid
    end
  end

  def controlling_player(_source, _metadata), do: nil

  defp player_owner(%{owner_guid: owner}) when is_integer(owner) and owner > 0 do
    if Guid.entity_type(owner) == :player, do: owner
  end

  defp player_owner(_metadata), do: nil

  def in_range?(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}, {world, px, py, pz}) do
    Math.distance({x, y, z}, {px, py, pz}) <= Experience.group_reward_distance()
  end

  def in_range?(_entity, _position), do: false
end
