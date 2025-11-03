defmodule ThistleTea.Game.Network.Message.CmsgAttackstop do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSTOP
  use ThistleTea.Game.Network.Opcodes, [:SMSG_ATTACKSTOP]

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    case Map.fetch(state, :attacking) do
      {:ok, target_guid} ->
        Logger.info("CMSG_ATTACKSTOP: #{target_guid}")

        %Message.SmsgAttackstop{
          player: state.guid,
          enemy: target_guid
        }
        |> World.broadcast_packet(state.character)

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
