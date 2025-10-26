defmodule ThistleTea.Game.Message.CmsgLogoutRequest do
  use ThistleTea.Game.ClientMessage, :CMSG_LOGOUT_REQUEST

  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Util.send_packet(%Message.SmsgLogoutResponse{result: 0, speed: 0})
    logout_timer = Process.send_after(self(), :logout_complete, 1_000)
    Map.put(state, :logout_timer, logout_timer)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
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
      account: Map.get(state, :account),
      conn: Map.get(state, :conn)
    }
  end
end
