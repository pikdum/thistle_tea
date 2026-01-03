defmodule ThistleTea.Game.Entity.Logic.Core do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.SpatialHash

  def update_packet(entity, update_type \\ :create_object2)
  def update_packet(%Mob{} = entity, update_type), do: update_packet(entity, update_type, :unit)
  def update_packet(%GameObject{} = entity, update_type), do: update_packet(entity, update_type, :game_object)
  def update_packet(%ThistleTea.Character{} = entity, update_type), do: update_packet(entity, update_type, :player)

  def update_packet(entity, update_type, object_type) do
    %UpdateObject{
      update_type: update_type,
      object_type: object_type
    }
    |> struct(Map.from_struct(entity))
    |> UpdateObject.to_packet()
  end

  def take_damage(%{unit: %Unit{health: health} = unit} = entity, damage) do
    new_health = max(health - damage, 0)

    %{entity | unit: %{unit | health: new_health}}
    |> maybe_dead()
  end

  defp maybe_dead(
         %{internal: %Internal{} = internal, unit: %Unit{health: 0} = unit, movement_block: %MovementBlock{} = mb} =
           entity
       ) do
    unit = %{unit | target: 0}
    internal = %{internal | in_combat: false, running: false}
    mb = %{mb | movement_flags: 0}
    %{entity | unit: unit, internal: internal, movement_block: mb}
  end

  defp maybe_dead(entity), do: entity

  def set_position(%Mob{} = entity), do: set_position(entity, :mobs)
  def set_position(%GameObject{} = entity), do: set_position(entity, :game_objects)

  def set_position(
        %{
          object: %Object{guid: guid},
          movement_block: %MovementBlock{position: {x, y, z, _o}},
          internal: %Internal{map: map}
        },
        table
      ) do
    SpatialHash.update(table, guid, self(), map, x, y, z)
  end

  def remove_position(%Mob{} = entity), do: remove_position(entity, :mobs)
  def remove_position(%GameObject{} = entity), do: remove_position(entity, :game_objects)

  def remove_position(%{object: %Object{guid: guid}}, table) do
    SpatialHash.remove(table, guid)
  end

  def nearby_players(
        %{internal: %Internal{map: map}, movement_block: %MovementBlock{position: {x, y, z, _o}}},
        range \\ 250
      ) do
    SpatialHash.query(:players, map, x, y, z, range)
  end
end
