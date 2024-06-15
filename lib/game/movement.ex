defmodule ThistleTea.Game.Movement do
  defmacro __using__(_) do
    quote do
      import ThistleTea.Game.UpdateObject
      import ThistleTea.Game.Character, only: [generate_random_equipment: 0]

      @update_type_values 0

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

      @impl GenServer
      def handle_cast({:handle_packet, msg, _size, body}, {socket, state})
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
        # TODO: try update_in
        character =
          Map.put(
            state.character,
            :movement,
            Map.merge(state.character.movement, decode_movement_info(body))
          )

        Logger.info("Movement: #{inspect(state.character.movement)}")

        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            if pid != self() do
              send(pid, {:send_packet, msg, state.packed_guid <> body})
            end
          end
        end)

        character =
          if msg === @msg_move_jump do
            character = Map.put(character, :equipment, generate_random_equipment())
            fields = get_update_fields(character)
            Logger.info("Fields: #{inspect(fields)}")
            packet = generate_packet(@update_type_values, 0, fields, nil)

            Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
              for {pid, _} <- entries do
                send(pid, {:send_update_packet, packet})
              end
            end)

            character
          else
            character
          end

        {:noreply, {socket, Map.put(state, :character, character)}, socket.read_timeout}
      end

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_standstatechange, _size, body}, {socket, state}) do
        <<animation_state::little-size(32)>> = body

        mb = Map.put(state.character.movement, :update_flag, @update_flag_living)

        # TODO: add :unit_bytes_1 to fields?
        fields =
          Map.put(get_update_fields(state.character), :unit_bytes_1, <<animation_state, 0, 0, 0>>)

        packet = generate_packet(@update_type_create_object2, @object_type_player, fields, mb)

        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            if pid != self() do
              send(pid, {:send_update_packet, packet})
            end
          end
        end)

        {:noreply, {socket, state}, socket.read_timeout}
      end
    end
  end
end
