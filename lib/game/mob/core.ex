defmodule ThistleTea.Game.Mob.Core do
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Game.Mob
  alias ThistleTea.Game.Utils.UpdateObject

  def update_packet(%Mob.Data{
        object: %FieldStruct.Object{} = object,
        unit: %FieldStruct.Unit{} = unit,
        movement_block: %FieldStruct.MovementBlock{} = movement_block
      }) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :unit,
      object: object,
      unit: unit,
      movement_block: movement_block
    }
    |> UpdateObject.to_packet()
  end

  def set_position(%Mob.Data{
        object: %FieldStruct.Object{} = object,
        movement_block: %FieldStruct.MovementBlock{} = movement_block,
        internal: %FieldStruct.Internal{} = internal
      }) do
    {x, y, z, _orientation} = movement_block.position

    SpatialHash.update(
      :mobs,
      object.guid,
      self(),
      internal.map,
      x,
      y,
      z
    )
  end

  def terminate(%Mob.Data{object: %FieldStruct.Object{} = object}) do
    SpatialHash.remove(:mobs, object.guid)
  end
end
