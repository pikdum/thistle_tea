defmodule ThistleTea.Game.GameObject.Core do
  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Game.GameObject
  alias ThistleTea.Game.Utils.UpdateObject

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  def update_packet(%GameObject.Data{
        object: %FieldStruct.Object{} = object,
        game_object: %FieldStruct.GameObject{} = game_object
      }) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :game_object,
      object: object,
      game_object: game_object,
      movement_block: %FieldStruct.MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {game_object.pos_x, game_object.pos_y, game_object.pos_z, game_object.facing}
      }
    }
    |> UpdateObject.to_packet()
  end

  def set_position(%GameObject.Data{
        object: %FieldStruct.Object{} = object,
        game_object: %FieldStruct.GameObject{} = game_object,
        internal: %FieldStruct.Internal{} = internal
      }) do
    SpatialHash.update(
      :game_objects,
      object.guid,
      self(),
      internal.map,
      game_object.pos_x,
      game_object.pos_y,
      game_object.pos_z
    )
  end

  def terminate(%GameObject.Data{object: %FieldStruct.Object{} = object}) do
    SpatialHash.remove(:game_objects, object.guid)
  end
end
