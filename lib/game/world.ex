defmodule ThistleTea.Game.World do
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Server.GameObject, as: GameObjectServer
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.SpatialHash

  def nearby_players(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}},
        range \\ 250
      ) do
    SpatialHash.query(:players, map, x, y, z, range)
  end

  def broadcast_packet(packet, entity, opts \\ [])

  def broadcast_packet(packets, entity, opts) when is_list(packets) do
    Enum.each(packets, fn packet -> broadcast_packet(packet, entity, opts) end)
  end

  def broadcast_packet(packet, entity, opts) do
    range = Keyword.get(opts, :range, 250)
    include_self? = Keyword.get(opts, :include_self?, true)
    source_guid = entity_guid(entity)

    nearby_players(entity, range)
    |> Enum.each(fn {guid, _distance} ->
      if include_self? or guid != source_guid do
        Network.send_packet(packet, guid)
      end
    end)
  end

  def start_entity(%GameObject{} = entity), do: start_entity(entity, GameObjectServer)
  def start_entity(%Mob{} = entity), do: start_entity(entity, MobServer)

  def start_entity(entity, server) do
    # TODO needed to prevent dupes, but maybe a registry is better
    case SpatialHash.get_entity(entity.object.guid) do
      nil -> DynamicSupervisor.start_child(EntitySupervisor, {server, entity})
      _ -> :ok
    end
  end

  def stop_entity(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(EntitySupervisor, pid)
  end

  def stop_entity(guid) when is_integer(guid) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> DynamicSupervisor.terminate_child(EntitySupervisor, pid)
      _ -> :ok
    end
  end

  def target_position(guid) when is_integer(guid) do
    case SpatialHash.get_entity(guid) do
      {^guid, map, x, y, z} -> {map, x, y, z}
      nil -> nil
    end
  end

  def distance_to_guid(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x1, y1, z1, _o}}},
        guid
      )
      when is_integer(guid) do
    case target_position(guid) do
      {^map, x2, y2, z2} -> SpatialHash.distance({x1, y1, z1}, {x2, y2, z2})
      _ -> nil
    end
  end

  defp entity_guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  defp entity_guid(%{guid: guid}) when is_integer(guid), do: guid
  defp entity_guid(_entity), do: nil
end
