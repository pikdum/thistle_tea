defmodule ThistleTea.Game.Movement do
  use ThistleTea.Opcodes,
      [
        :MSG_MOVE_START_FORWARD,
        :MSG_MOVE_START_BACKWARD,
        :MSG_MOVE_STOP,
        :MSG_MOVE_START_STRAFE_LEFT,
        :MSG_MOVE_START_STRAFE_RIGHT,
        :MSG_MOVE_STOP_STRAFE,
        :MSG_MOVE_JUMP,
        :MSG_MOVE_START_TURN_LEFT,
        :MSG_MOVE_START_TURN_RIGHT,
        :MSG_MOVE_STOP_TURN,
        :MSG_MOVE_START_PITCH_UP,
        :MSG_MOVE_START_PITCH_DOWN,
        :MSG_MOVE_STOP_PITCH,
        :MSG_MOVE_SET_RUN_MODE,
        :MSG_MOVE_SET_WALK_MODE,
        :MSG_MOVE_FALL_LAND,
        :MSG_MOVE_START_SWIM,
        :MSG_MOVE_STOP_SWIM,
        :MSG_MOVE_SET_FACING,
        :MSG_MOVE_SET_PITCH,
        :MSG_MOVE_HEARTBEAT,
        :CMSG_MOVE_FALL_RESET
      ]

  import ThistleTea.Game.Message.CmsgCharCreate, only: [generate_random_equipment: 0]
  import ThistleTea.Util, only: [send_update_packet: 1]

  alias ThistleTea.Game.FieldStruct.MovementBlock
  alias ThistleTea.Game.Message.CmsgCancelCast
  alias ThistleTea.Game.Utils.UpdateObject

  require Logger

  @spell_failed_moving 0x2E

  # TODO: this can crash, waiting for namigator fix
  # defp update_area(character) do
  #   %{x: x, y: y, z: z} = character.movement

  #   case ThistleTea.Pathfinding.get_zone_and_area(character.map, {x, y, z}) do
  #     {_zone, area} -> Map.put(character, :area, area)
  #     nil -> character
  #   end
  # end

  defp randomize_equipment(state, msg) do
    if msg === @msg_move_jump do
      character = Map.put(state.character, :equipment, generate_random_equipment())

      update_object =
        character |> ThistleTea.Character.get_update_fields() |> Map.put(:update_type, :values)

      packet = UpdateObject.to_packet(update_object)

      # item packets
      UpdateObject.get_item_packets(character.equipment)
      |> Enum.each(fn packet -> send_update_packet(packet) end)

      for pid <- Map.get(state, :player_pids, []) do
        GenServer.cast(pid, {:send_update_packet, packet})
      end

      Map.put(state, :character, character)
    else
      state
    end
  end

  def handle_packet(msg, body, %{ready: true} = state)
      when msg in [
             @msg_move_start_forward,
             @msg_move_start_backward,
             @msg_move_stop,
             @msg_move_start_strafe_left,
             @msg_move_start_strafe_right,
             @msg_move_stop_strafe,
             @msg_move_jump,
             @msg_move_start_turn_left,
             @msg_move_start_turn_right,
             @msg_move_stop_turn,
             @msg_move_start_pitch_up,
             @msg_move_start_pitch_down,
             @msg_move_stop_pitch,
             @msg_move_set_run_mode,
             @msg_move_set_walk_mode,
             @msg_move_fall_land,
             @msg_move_start_swim,
             @msg_move_stop_swim,
             @msg_move_set_facing,
             @msg_move_set_pitch,
             @msg_move_heartbeat,
             @cmsg_move_fall_reset
           ] do
    state =
      with %MovementBlock{position: {x0, y0, z0, _}} <- state.character.movement,
           %MovementBlock{position: {x1, y1, z1, _}} = movement <-
             MovementBlock.from_binary(body, state.character.movement),
           %{map: map} = character <- state.character |> Map.put(:movement, movement) do
        if x0 != x1 or y0 != y1 or z0 != z1 do
          SpatialHash.update(:players, state.guid, self(), map, x1, y1, z1)

          Map.put(state, :character, character)
          |> CmsgCancelCast.cancel_spell(@spell_failed_moving)
        else
          Map.put(state, :character, character)
        end
      else
        nil -> state
      end
      |> randomize_equipment(msg)

    # broadcast movement to nearby players
    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_packet, msg, state.packed_guid <> body})
      end
    end

    {:continue, state}
  end

  def handle_packet(_msg, _body, state) do
    {:continue, state}
  end
end
