defmodule ThistleTea.Game.Movement do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.PlayerStorage

      import ThistleTea.Util, only: [pack_guid: 1]

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
        # TODO: no real need for us to persist on every movement change
        # Logger.info("[GameServer] movement packet: #{inspect(msg, base: :hex)}")
        # player_pid = Map.get(state, :player_pid)
        # Logger.info("[GameServer] player_pid: #{inspect(player_pid)}")
        # PlayerStorage.update_movement(player_pid, body)

        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            if pid != self() do
              send(pid, {:send_packet, msg, pack_guid(state.guid) <> body})
            end
          end
        end)

        {:noreply, {socket, state}}
      end
    end
  end
end
