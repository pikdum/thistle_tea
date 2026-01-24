defmodule ThistleTea.Game.Entity.Data.GameObject do
  import Bitwise, only: [|||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.GameObject
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Guid

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  defstruct object: %Object{},
            game_object: %GameObject{},
            movement_block: %MovementBlock{},
            internal: %Internal{}

  def build(%Mangos.GameObject{game_object_template: %Mangos.GameObjectTemplate{} = ot} = o) do
    event =
      case o.game_event_game_object do
        %Mangos.GameEventGameObject{event: event} -> event
        _ -> nil
      end

    %__MODULE__{
      object: %Object{
        guid: Guid.from_low_guid(:game_object, o.id, o.guid),
        entry: o.id,
        scale_x: ot.size
      },
      game_object: %GameObject{
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
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position: {o.position_x, o.position_y, o.position_z, o.orientation}
      },
      internal: %Internal{map: o.map, event: event}
    }
  end
end
