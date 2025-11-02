defmodule ThistleTea.Game.Network.Message.CmsgSetsheathed do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SETSHEATHED

  alias ThistleTea.Game.Network.UpdateObject

  require Logger

  defstruct [:sheath_state]

  @impl ClientMessage
  def handle(
        %__MODULE__{sheath_state: sheath_state},
        %{character: %Character{unit: %FieldStruct.Unit{} = unit} = character} = state
      ) do
    Logger.info("CMSG_SETSHEATHED")
    character = %{character | unit: %{unit | sheath_state: sheath_state}}

    packet =
      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> UpdateObject.to_packet()

    # TODO: this doesn't show the unsheathing animation
    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_update_packet, packet})
    end

    %{state | character: character}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<sheath_state::little-size(32)>> = payload

    %__MODULE__{
      sheath_state: sheath_state
    }
  end
end
