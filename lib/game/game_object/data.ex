defmodule ThistleTea.Game.GameObject.Data do
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.DB.Mangos

  @game_object_guid_offset 0xF1100000

  defstruct object: %FieldStruct.Object{},
            game_object: %FieldStruct.GameObject{},
            movement_block: %FieldStruct.MovementBlock{},
            internal: %FieldStruct.Internal{}

  def build(%Mangos.GameObject{} = o) do
    %__MODULE__{
      object: %FieldStruct.Object{
        guid: o.guid + @game_object_guid_offset,
        entry: o.id,
        scale_x: o.game_object_template.size
      },
      game_object: %FieldStruct.GameObject{
        display_id: o.game_object_template.display_id,
        flags: o.game_object_template.flags,
        rotation0: o.rotation0,
        rotation1: o.rotation1,
        rotation2: o.rotation2,
        rotation3: o.rotation3,
        state: o.state,
        pos_x: o.position_x,
        pos_y: o.position_y,
        pos_z: o.position_z,
        facing: o.orientation,
        faction: o.game_object_template.faction,
        type_id: o.game_object_template.type,
        anim_progress: o.animprogress
      },
      movement_block: %FieldStruct.MovementBlock{},
      internal: %FieldStruct.Internal{map: o.map}
    }
  end
end
