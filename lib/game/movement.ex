defmodule ThistleTea.Game.Movement do
  defmacro __using__(_) do
    quote do
      import ThistleTea.Game.UpdateObject

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
        <<
          # ignore these
          _flags::little-size(32),
          _time::little-size(32),
          # we only want position here
          x::little-float-size(32),
          y::little-float-size(32),
          z::little-float-size(32),
          orientation::little-float-size(32),
          _rest::binary
        >> = body

        character =
          Map.merge(state.character, %{
            x: x,
            y: y,
            z: z,
            orientation: orientation
          })

        Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
          for {pid, _} <- entries do
            if pid != self() do
              send(pid, {:send_packet, msg, state.packed_guid <> body})
            end
          end
        end)

        {:noreply, {socket, Map.put(state, :character, character)}, socket.read_timeout}
      end

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_standstatechange, _size, body}, {socket, state}) do
        <<animation_state::little-size(32)>> = body

        c = state.character

        # TODO: do i need to include everything every time, or just some fields?
        # TODO: refactor this out, have character or similar generate this
        mb = %{
          update_flag: @update_flag_living,
          movement_flags: 0,
          position: {c.x, c.y, c.z, c.orientation},
          fall_time: 0.0,
          walk_speed: 1.0,
          # run_speed: 7.0,
          run_speed: 20.0,
          run_back_speed: 4.5,
          swim_speed: 0.0,
          swim_back_speed: 0.0,
          turn_rate: 3.1415
        }

        fields = %{
          object_guid: c.id,
          object_type: 25,
          object_scale_x: 1.0,
          unit_health: 100,
          unit_power_1: 100,
          unit_power_2: 100,
          unit_power_3: 100,
          unit_power_4: 100,
          unit_power_5: 100,
          unit_max_health: 100,
          unit_max_power_1: 100,
          unit_max_power_2: 100,
          unit_max_power_3: 100,
          unit_max_power_4: 100,
          unit_max_power_5: 100,
          unit_level: c.level,
          unit_faction_template: 1,
          unit_bytes_0: <<c.race, c.class, c.gender, 1>>,
          # TODO: maybe this should be on character instead
          unit_display_id: state.unit_display_id,
          unit_native_display_id: state.unit_display_id,
          player_flags: 0,
          player_features: <<c.skin, c.face, c.hair_style, c.hair_color>>,
          player_xp: 1,
          player_next_level_xp: 100,
          player_rest_state_experience: 100,
          # TODO: handle empty equipment slot
          player_visible_item_1_0: c.equipment.head.entry,
          player_visible_item_2_0: c.equipment.neck.entry,
          player_visible_item_3_0: c.equipment.shoulders.entry,
          player_visible_item_4_0: c.equipment.body.entry,
          player_visible_item_5_0: c.equipment.chest.entry,
          player_visible_item_6_0: c.equipment.waist.entry,
          player_visible_item_7_0: c.equipment.legs.entry,
          player_visible_item_8_0: c.equipment.feet.entry,
          player_visible_item_9_0: c.equipment.wrists.entry,
          player_visible_item_10_0: c.equipment.hands.entry,
          player_visible_item_11_0: c.equipment.finger1.entry,
          player_visible_item_12_0: c.equipment.finger2.entry,
          player_visible_item_13_0: c.equipment.trinket1.entry,
          player_visible_item_14_0: c.equipment.trinket2.entry,
          player_visible_item_15_0: c.equipment.back.entry,
          player_visible_item_16_0: c.equipment.mainhand.entry,
          # player_visible_item_17_0: c.equipment.offhand.entry,
          # player_visible_item_18_0: c.equipment.ranged.entry,
          player_visible_item_19_0: c.equipment.tabard.entry,
          unit_bytes_1: <<animation_state, 0, 0, 0>>
        }

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
