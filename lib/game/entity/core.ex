defmodule ThistleTea.Game.Entity.Core do
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Game.GameObject
  alias ThistleTea.Game.Mob
  alias ThistleTea.Game.Utils.UpdateObject

  def update_packet(%Mob.Data{} = entity), do: update_packet(entity, :unit)
  def update_packet(%GameObject.Data{} = entity), do: update_packet(entity, :game_object)

  def update_packet(entity, object_type) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: object_type
    }
    |> struct(Map.from_struct(entity))
    |> UpdateObject.to_packet()
  end

  def take_damage(
        %{
          unit: %FieldStruct.Unit{health: health} = unit,
          movement_block: %FieldStruct.MovementBlock{movement_flags: movement_flags} = mb
        } = entity,
        damage
      ) do
    new_health = max(health - damage, 0)
    new_movement_flags = if new_health == 0, do: 0, else: movement_flags
    {:ok, %{entity | unit: %{unit | health: new_health}, movement_block: %{mb | movement_flags: new_movement_flags}}}
  end

  def set_position(%Mob.Data{} = entity), do: set_position(entity, :mobs)
  def set_position(%GameObject.Data{} = entity), do: set_position(entity, :game_objects)

  def set_position(
        %{
          object: %FieldStruct.Object{guid: guid},
          movement_block: %FieldStruct.MovementBlock{position: {x, y, z, _o}},
          internal: %FieldStruct.Internal{map: map}
        },
        table
      ) do
    SpatialHash.update(
      table,
      guid,
      self(),
      map,
      x,
      y,
      z
    )
  end

  def remove_position(%Mob.Data{} = entity), do: remove_position(entity, :mobs)
  def remove_position(%GameObject.Data{} = entity), do: remove_position(entity, :game_objects)

  def remove_position(%{object: %FieldStruct.Object{guid: guid}}, table) do
    SpatialHash.remove(table, guid)
  end

  def nearby_players(
        %{
          internal: %FieldStruct.Internal{map: map},
          movement_block: %FieldStruct.MovementBlock{position: {x, y, z, _o}}
        },
        range \\ 250
      ) do
    SpatialHash.query(:players, map, x, y, z, range)
  end
end
