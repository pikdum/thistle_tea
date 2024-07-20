defmodule ThistleTea.Game.Movement do
  import ThistleTea.Character, only: [get_update_fields: 1]
  import ThistleTea.Game.Character, only: [generate_random_equipment: 0]
  import ThistleTea.Game.UpdateObject, only: [generate_packet: 2, decode_movement_info: 1]
  import ThistleTea.Util, only: [within_range: 2, send_update_packet: 1, send_packet: 2]

  require Logger

  @update_type_values 0
  @smsg_destroy_object 0x0AA

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

  def handle_packet(msg, body, state)
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
    %{x: x0, y: y0, z: z0} = state.character.movement

    # TODO: try update_in
    character =
      Map.put(
        state.character,
        :movement,
        Map.merge(state.character.movement, decode_movement_info(body))
      )

    %{x: x1, y: y1, z: z1} = character.movement

    state =
      if x0 != x1 and y0 != y1 and z0 != z1 do
        ThistleTea.Game.Spell.cancel_spell(state, @spell_failed_moving)
      else
        state
      end

    # update registry metadata
    # this feels like a hack, why can't i just update?
    # TODO: maybe move position data to ets?
    # TODO: when destroying player, should also destroy self from them
    Registry.unregister(ThistleTea.PlayerRegistry, character.map)

    {:ok, _} =
      Registry.register(ThistleTea.PlayerRegistry, character.map, {state.guid, x1, y1, z1})

    Registry.dispatch(ThistleTea.PlayerRegistry, character.map, fn entries ->
      for {pid, values} <- entries do
        {guid, x2, y2, z2} = values
        in_range = within_range({x1, y1, z1}, {x2, y2, z2})

        # broadcast movement packets
        if pid != self() and in_range do
          GenServer.cast(pid, {:send_packet, msg, state.packed_guid <> body})
        end

        # spawn in players as you move around
        cond do
          pid == self() ->
            :ok

          in_range && not :ets.member(state.spawned_guids, guid) ->
            GenServer.cast(pid, {:send_update_to, self()})
            :ets.insert(state.spawned_guids, {guid, true})

          not in_range && :ets.member(state.spawned_guids, guid) ->
            send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
            :ets.delete(state.spawned_guids, guid)

          true ->
            :ok
        end
      end
    end)

    # spawn in mobs as you move around
    Registry.dispatch(ThistleTea.MobRegistry, state.character.map, fn entries ->
      for {pid, values} <- entries do
        {guid, x2, y2, z2} = values
        in_range = within_range({x1, y1, z1}, {x2, y2, z2})

        cond do
          in_range && not :ets.member(state.spawned_guids, guid) ->
            GenServer.cast(pid, {:send_update_to, self()})
            :ets.insert(state.spawned_guids, {guid, true})

          not in_range && :ets.member(state.spawned_guids, guid) ->
            send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
            :ets.delete(state.spawned_guids, guid)

          true ->
            :ok
        end
      end
    end)

    # randomizes equipment on jump
    character =
      if msg === @msg_move_jump do
        character = Map.put(character, :equipment, generate_random_equipment())
        fields = get_update_fields(character)
        packet = generate_packet(@update_type_values, fields)

        Registry.dispatch(ThistleTea.PlayerRegistry, state.character.map, fn entries ->
          for {pid, values} <- entries do
            {_guid, x2, y2, z2} = values

            if within_range({x1, y1, z1}, {x2, y2, z2}) do
              GenServer.cast(pid, {:send_update_packet, packet})
            end
          end
        end)

        character
      else
        character
      end

    {:continue, Map.put(state, :character, character)}
  end

  def handle_packet(@cmsg_standstatechange, body, state) do
    <<animation_state::little-size(32)>> = body

    # TODO: add :unit_bytes_1 to fields?
    fields =
      Map.put(get_update_fields(state.character), :unit_bytes_1, <<animation_state, 0, 0, 0>>)

    packet = generate_packet(@update_type_values, fields)

    Registry.dispatch(ThistleTea.PlayerRegistry, "logged_in", fn entries ->
      for {pid, _} <- entries do
        if pid != self() do
          GenServer.cast(pid, {:send_update_packet, packet})
        end
      end
    end)

    {:continue, state}
  end
end
