defmodule ThistleTea.Game.Message.CmsgStandstatechange do
  use ThistleTea.Game.ClientMessage, :CMSG_STANDSTATECHANGE

  alias ThistleTea.Game.Utils.UpdateObject

  defstruct [:animation_state]

  @impl ClientMessage
  def handle(
        %__MODULE__{animation_state: animation_state},
        %{character: %Character{unit: %FieldStruct.Unit{} = unit} = character} = state
      ) do
    character = %{character | unit: %{unit | stand_state: animation_state}}

    packet =
      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> UpdateObject.to_packet()

    # Broadcast to nearby players
    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_update_packet, packet})
      end
    end

    # TODO: for some reason players are stuck sitting
    %{state | character: character}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<animation_state::little-size(32)>> = payload

    %__MODULE__{
      animation_state: animation_state
    }
  end
end
