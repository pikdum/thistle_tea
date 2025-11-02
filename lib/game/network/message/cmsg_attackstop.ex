defmodule ThistleTea.Game.Network.Message.CmsgAttackstop do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSTOP
  use ThistleTea.Game.Network.Opcodes, [:SMSG_ATTACKSTOP]

  import ThistleTea.Util, only: [pack_guid: 1]

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        payload =
          state.packed_guid <>
            pack_guid(target_guid) <>
            <<0::little-size(32)>>

        Logger.info("CMSG_ATTACKSTOP: #{target_guid}")

        for pid <- Map.get(state, :player_pids, []) do
          GenServer.cast(pid, {:send_packet, @smsg_attackstop, payload})
        end

        Map.delete(state, :attacking)

      :error ->
        state
    end
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
