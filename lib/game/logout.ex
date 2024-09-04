defmodule ThistleTea.Game.Logout do
  import ThistleTea.Util, only: [send_packet: 2]

  require Logger

  @cmsg_logout_request 0x04B
  @smsg_logout_response 0x04C

  @cmsg_logout_cancel 0x04E
  @smsg_logout_cancel_ack 0x04F

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

    # cleanup
    # TODO: refactor out player registry
    Registry.keys(ThistleTea.PlayerRegistry, self())
    |> Enum.each(&Registry.unregister(ThistleTea.PlayerRegistry, &1))

    # broadcast destroy object
    if Map.get(state, :guid) do
      # remove from map
      SpatialHash.remove(:players, state.guid)

      for pid <- Map.get(state, :player_pids, []) do
        if pid != self() do
          GenServer.cast(pid, {:destroy_object, state.guid})
        end
      end
    end

    # reset state so nothing lingers
    %{
      seed: state.seed,
      crypto_pid: Map.get(state, :crypto_pid),
      account: Map.get(state, :account)
    }
  end
end
