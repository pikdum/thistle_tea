defmodule ThistleTea.Game.Movement do
  import ThistleTea.Game.Character, only: [generate_random_equipment: 0]

  import ThistleTea.Game.UpdateObject, only: [get_item_packets: 1]

  import ThistleTea.Util, only: [send_update_packet: 1]

  alias ThistleTea.Game.Utils.NewUpdateObject
  alias ThistleTea.Game.Utils.MovementBlock

  require Logger

  @msg_move_start_forward 0x0B5
  @msg_move_start_backward 0x0B6
  @msg_move_stop 0x0B7
  @msg_move_start_strafe_left 0x0B8
  @msg_move_start_strafe_right 0x0B9
  @msg_move_stop_strafe 0x0BA
  @msg_move_jump 0x0BB
  @msg_move_start_turn_left 0x0BC
  @msg_move_start_turn_right 0x0BD
  @msg_move_stop_turn 0x0BE
  @msg_move_start_pitch_up 0x0BF
  @msg_move_start_pitch_down 0x0C0
  @msg_move_stop_pitch 0x0C1
  @msg_move_set_run_mode 0x0C2
  @msg_move_set_walk_mode 0x0C3
  @msg_move_fall_land 0x0C9
  @msg_move_start_swim 0x0CA
  @msg_move_stop_swim 0x0CB
  @msg_move_set_facing 0x0DA
  @msg_move_set_pitch 0x0DB
  @msg_move_heartbeat 0x0EE
  @cmsg_move_fall_reset 0x2CA

  @cmsg_standstatechange 0x101

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

      packet = NewUpdateObject.to_packet(update_object)

      # item packets
      get_item_packets(character.equipment)
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
             MovementBlock.from_binary(body),
           movement <- Map.merge(state.character.movement, movement),
           %{map: map} = character <- state.character |> Map.put(:movement, movement) do
        if x0 != x1 or y0 != y1 or z0 != z1 do
          SpatialHash.update(:players, state.guid, self(), map, x1, y1, z1)

          Map.put(state, :character, character)
          |> ThistleTea.Game.Spell.cancel_spell(@spell_failed_moving)
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

  def handle_packet(@cmsg_standstatechange, body, state) do
    <<animation_state::little-size(32)>> = body

    # TODO: add :unit_bytes_1 to fields?
    update_object = ThistleTea.Character.get_update_fields(state.character)

    update_object = %{
      update_object
      | unit: Map.put(update_object.unit, :stand_state, animation_state),
        update_type: :values
    }

    packet = NewUpdateObject.to_packet(update_object)

    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_update_packet, packet})
      end
    end

    {:continue, state}
  end

  def handle_packet(_msg, _body, state) do
    {:continue, state}
  end
end
