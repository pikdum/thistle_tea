defmodule ThistleTea.Game.Message.CmsgSetsheathed do
  use ThistleTea.Game.ClientMessage, :CMSG_SETSHEATHED

  alias ThistleTea.Game.Utils.UpdateObject

  require Logger

  defstruct [:sheath_state]

  @impl ClientMessage
  def handle(%__MODULE__{sheath_state: sheath_state}, state) do
    Logger.info("CMSG_SETSHEATHED")
    character = Map.put(state.character, :sheath_state, sheath_state)

    update_object =
      character |> ThistleTea.Character.get_update_fields() |> Map.put(:update_type, :values)

    packet = UpdateObject.to_packet(update_object)

    # TODO: this doesn't show the unsheathing animation
    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_update_packet, packet})
    end

    Map.put(state, :character, character)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<sheath_state::little-size(32)>> = payload

    %__MODULE__{
      sheath_state: sheath_state
    }
  end
end
