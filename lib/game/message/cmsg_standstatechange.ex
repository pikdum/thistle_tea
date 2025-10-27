defmodule ThistleTea.Game.Message.CmsgStandstatechange do
  use ThistleTea.Game.ClientMessage, :CMSG_STANDSTATECHANGE

  alias ThistleTea.Game.Utils.UpdateObject

  defstruct [:animation_state]

  @impl ClientMessage
  def handle(%__MODULE__{animation_state: animation_state}, state) do
    # Update the character's stand state
    update_object = struct(UpdateObject, state.character)

    update_object = %{
      update_object
      | unit: Map.put(update_object.unit, :stand_state, animation_state),
        update_type: :values
    }

    packet = UpdateObject.to_packet(update_object)

    # Broadcast to nearby players
    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_update_packet, packet})
      end
    end

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<animation_state::little-size(32)>> = payload

    %__MODULE__{
      animation_state: animation_state
    }
  end
end
