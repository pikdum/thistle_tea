defmodule ThistleTea.GameObject do
  use GenServer
  import ThistleTea.Game.UpdateObject, only: [generate_packet: 4]
  import Bitwise, only: [|||: 2]
  require Logger

  @game_object_guid_offset 0xF1100000

  @update_type_create_object2 3
  @object_type_game_object 5

  @update_flag_all 0x10
  @update_flag_has_position 0x40

  def start_link(game_object) do
    GenServer.start_link(__MODULE__, game_object, hibernate_after: 30_000)
  end

  def update_packet(state) do
    fields =
      %{
        object_guid: state.game_object.guid,
        # TODO: maybe change some names so this can't be confused with @object_type_*?
        # TODO: this is probably why my item updates didn't work earlier
        # object + game_object
        object_type: 33,
        object_entry: state.game_object.id,
        object_scale_x: state.game_object.game_object_template.size,
        game_object_display_id: state.game_object.game_object_template.display_id,
        game_object_flags: state.game_object.game_object_template.flags,
        game_object_rotation0: state.game_object.rotation0,
        game_object_rotation1: state.game_object.rotation1,
        game_object_rotation2: state.game_object.rotation2,
        game_object_rotation3: state.game_object.rotation3,
        game_object_state: state.game_object.state,
        game_object_pos_x: state.game_object.position_x,
        game_object_pos_y: state.game_object.position_y,
        game_object_pos_z: state.game_object.position_z,
        game_object_facing: state.game_object.orientation,
        game_object_faction: state.game_object.game_object_template.faction,
        game_object_type_id: state.game_object.game_object_template.type,
        game_object_animprogress: state.game_object.animprogress
      }

    mb = %{
      update_flag: @update_flag_all ||| @update_flag_has_position,
      x: state.game_object.position_x,
      y: state.game_object.position_y,
      z: state.game_object.position_z,
      orientation: state.game_object.orientation
    }

    generate_packet(@update_type_create_object2, @object_type_game_object, fields, mb)
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
