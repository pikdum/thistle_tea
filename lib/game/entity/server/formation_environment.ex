defmodule ThistleTea.Game.Entity.Server.FormationEnvironment do
  @moduledoc """
  Collects formation membership and the leader's published motion without
  requesting state from another entity process.
  """
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Formation
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Formation, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.AI.BT.Formation, as: FormationLogic
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.Spline

  @controlled_flags 0x00040000 ||| 0x00400000 ||| 0x00800000 ||| 0x00000008

  def snapshot(%Mob{object: %{guid: guid}, internal: %{world: world}}, now) do
    case CreatureGroups.formation(world, guid) do
      %Formation{leader_guid: leader} = membership when is_integer(leader) ->
        metadata = Metadata.get(leader) || %{}
        position = same_world_position(leader, world, now)

        ready? =
          match?({^world, _, _, _}, position) and Map.get(metadata, :alive?) == true and
            Map.get(metadata, :in_combat) != true and ((Map.get(metadata, :unit_flags) || 0) &&& @controlled_flags) == 0

        snapshot = %Snapshot{
          membership: membership,
          leader_position: position,
          leader_orientation: Map.get(metadata, :orientation),
          leader_ready?: ready?
        }

        put_motion(snapshot, Position.projection(leader), now)

      %Formation{} = membership ->
        %Snapshot{membership: membership}

      nil ->
        nil
    end
  end

  def snapshot(_entity, _now), do: nil

  def respawn_position(%Mob{object: %{guid: guid}, internal: %{world: world}}, now) do
    case CreatureGroups.formation(world, guid) do
      %Formation{original_guid: leader, original_spawn: spawn, member: %Member{flags: flags} = member}
      when is_integer(leader) and (flags &&& 1) != 0 ->
        metadata = Metadata.get(leader) || %{}
        current = same_world_position(leader, world, now)
        position = if metadata[:alive?] and current, do: Tuple.delete_at(current, 0), else: spawn
        orientation = metadata[:orientation] || 0.0
        respawn_offset(world.map_id, position, orientation, member)

      _membership ->
        nil
    end
  end

  defp respawn_offset(map, {x, y, z}, orientation, member) do
    position = FormationLogic.offset({x, y, z}, orientation, member)
    {px, py, pz} = Pathfinding.snap_to_ground(map, position)
    {px, py, pz, :math.atan2(y - py, x - px)}
  end

  defp respawn_offset(_map, _position, _orientation, _member), do: nil

  defp same_world_position(guid, world, now) do
    case World.position(guid, now) do
      {^world, _, _, _} = position -> position
      _position -> nil
    end
  end

  defp put_motion(snapshot, %Spline{origin: origin, nodes: nodes, started_at: started, duration_ms: duration}, now)
       when started + duration > now do
    %{snapshot | path: [origin | nodes], started_at: started, arrives_at: started + duration}
  end

  defp put_motion(snapshot, _projection, _now), do: snapshot
end
