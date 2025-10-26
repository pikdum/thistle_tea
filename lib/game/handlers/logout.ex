defmodule ThistleTea.Game.Logout do
  use ThistleTea.Opcodes, [
    :CMSG_LOGOUT_REQUEST,
    :SMSG_LOGOUT_RESPONSE,
    :CMSG_LOGOUT_CANCEL,
    :SMSG_LOGOUT_CANCEL_ACK
  ]

  import ThistleTea.Util, only: [send_packet: 2]

  alias ThistleTea.Game.Connection

  require Logger

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

    if Map.get(state, :spawn_timer) do
      :timer.cancel(state.spawn_timer)
    end

    if Map.get(state, :guid) do
      # remove from map
      SpatialHash.remove(:players, state.guid)

      # leave all chat channels
      ThistleTea.ChatChannel
      |> Registry.keys(self())
      |> Enum.each(fn channel ->
        ThistleTea.ChatChannel
        |> Registry.unregister(channel)
      end)

      # broadcast destroy object
      for pid <- Map.get(state, :player_pids, []) do
        if pid != self() do
          GenServer.cast(pid, {:destroy_object, state.guid})
        end
      end
    end

    # reset state so nothing lingers
    %{
      seed: state.seed,
      conn: %Connection{},
      account: Map.get(state, :account)
    }
  end
end
