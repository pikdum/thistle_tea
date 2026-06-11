defmodule ThistleTea.Game.Network.Message.CmsgSetActionButton do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTION_BUTTON

  @max_action_buttons 120

  defstruct [:button, :packed_data]

  @impl ClientMessage
  def handle(%__MODULE__{button: button}, state) when button >= @max_action_buttons do
    state
  end

  def handle(%__MODULE__{button: button, packed_data: packed_data}, state) do
    internal = state.character.internal

    action_buttons = Map.get(internal, :action_buttons) || %{}

    action_buttons =
      case packed_data do
        0 -> Map.delete(action_buttons, button)
        _ -> Map.put(action_buttons, button, packed_data)
      end

    put_in(state.character.internal, Map.put(internal, :action_buttons, action_buttons))
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<button::little-size(8), packed_data::little-size(32)>> = payload

    %__MODULE__{
      button: button,
      packed_data: packed_data
    }
  end
end
