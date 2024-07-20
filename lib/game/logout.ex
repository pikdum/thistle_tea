defmodule ThistleTea.Game.Logout do
  import ThistleTea.Util, only: [send_packet: 2, within_range: 2]

  require Logger

  @cmsg_logout_request 0x04B
  @smsg_logout_response 0x04C

  @cmsg_logout_cancel 0x04E
  @smsg_logout_cancel_ack 0x04F

  @smsg_destroy_object 0x0AA

  def handle_packet(@cmsg_logout_request, _body, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    send_packet(@smsg_logout_response, <<0::little-size(32)>>)
    logout_timer = Process.send_after(self(), :logout_complete, 1_000)
    {:continue, Map.put(state, :logout_timer, logout_timer)}
  end

  def handle_packet(@cmsg_logout_cancel, _body, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    state =
      case Map.get(state, :logout_timer, nil) do
        nil ->
          state

        timer ->
          Process.cancel_timer(timer)
          Map.delete(state, :logout_timer)
      end

    send_packet(@smsg_logout_cancel_ack, <<>>)
    {:continue, state}
  end

  def handle_logout(state) do
    # save current character state
    if Map.get(state, :character) do
      ThistleTea.Character.save(state.character)
    end

    # remove from pubsub
    Registry.unregister(ThistleTea.PlayerRegistry, "all")
    Registry.unregister(ThistleTea.PlayerRegistry, state.character.map)

    # broadcast destroy object
    if Map.get(state, :guid) do
      Registry.dispatch(ThistleTea.PlayerRegistry, state.character.map, fn entries ->
        {x1, y1, z1} =
          {state.character.movement.x, state.character.movement.y, state.character.movement.z}

        for {pid, values} <- entries do
          {_guid, x2, y2, z2} = values

          if within_range({x1, y1, z1}, {x2, y2, z2}) do
            GenServer.cast(
              pid,
              {:send_packet, @smsg_destroy_object, <<state.guid::little-size(64)>>}
            )
          end
        end
      end)
    end
  end
end
