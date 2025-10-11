defmodule ThistleTea.Game.GameObject.Data do
  import Bitwise, only: [|||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.FieldStruct

  @game_object_guid_offset 0xF1100000

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  defstruct object: %FieldStruct.Object{},
            game_object: %FieldStruct.GameObject{},
            movement_block: %FieldStruct.MovementBlock{},
            internal: %FieldStruct.Internal{}

  def build(%Mangos.GameObject{game_object_template: %Mangos.GameObjectTemplate{} = ot} = o) do
    %__MODULE__{
      object: %FieldStruct.Object{
        guid: o.guid + @game_object_guid_offset,
        entry: o.id,
        scale_x: ot.size
      },
      game_object: %FieldStruct.GameObject{
        display_id: ot.display_id,
        flags: ot.flags,
        rotation0: o.rotation0,
        rotation1: o.rotation1,
        rotation2: o.rotation2,
        rotation3: o.rotation3,
        state: o.state,
        pos_x: o.position_x,
        pos_y: o.position_y,
        pos_z: o.position_z,
        facing: o.orientation,
        faction: ot.faction,
        type_id: ot.type,
        anim_progress: o.animprogress
      },
      movement_block: %FieldStruct.MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {o.position_x, o.position_y, o.position_z, o.orientation}
      },
      internal: %FieldStruct.Internal{map: o.map}
    }
  end
end
