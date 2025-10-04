defmodule ThistleTea.GameObject do
  use GenServer
  import Bitwise, only: [|||: 2]
  require Logger

  alias ThistleTea.Game.Entities.Data.Object
  alias ThistleTea.Game.Entities.Data.GameObject
  alias ThistleTea.Game.Utils.UpdateObject
  alias ThistleTea.Game.Utils.MovementBlock

  @game_object_guid_offset 0xF1100000

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  def start_link(game_object) do
    GenServer.start_link(__MODULE__, game_object, hibernate_after: 15_000)
  end

  def update_packet(state) do
    update_object = %UpdateObject{
      update_type: :create_object2,
      object_type: :game_object,
      object: %Object{
        guid: state.game_object.guid,
        entry: state.game_object.id,
        scale_x: state.game_object.game_object_template.size
      },
      game_object: %GameObject{
        display_id: state.game_object.game_object_template.display_id,
        flags: state.game_object.game_object_template.flags,
        rotation0: state.game_object.rotation0,
        rotation1: state.game_object.rotation1,
        rotation2: state.game_object.rotation2,
        rotation3: state.game_object.rotation3,
        state: state.game_object.state,
        pos_x: state.game_object.position_x,
        pos_y: state.game_object.position_y,
        pos_z: state.game_object.position_z,
        facing: state.game_object.orientation,
        faction: state.game_object.game_object_template.faction,
        type_id: state.game_object.game_object_template.type,
        anim_progress: state.game_object.animprogress
      },
      movement_block: %MovementBlock{
        update_flag: @update_flag_all ||| @update_flag_has_position,
        position:
          {state.game_object.position_x, state.game_object.position_y,
           state.game_object.position_z, state.game_object.orientation}
      }
    }

    UpdateObject.to_packet(update_object)
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = update_packet(state)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  @impl GenServer
  def init(game_object) do
    game_object = Map.put(game_object, :guid, game_object.guid + @game_object_guid_offset)

    SpatialHash.update(
      :game_objects,
      game_object.guid,
      self(),
      game_object.map,
      game_object.position_x,
      game_object.position_y,
      game_object.position_z
    )

    state = %{
      game_object: game_object
    }

    {:ok, state}
  end
end
