defmodule ThistleTea.Game.Inbound.CmsgSetActionButton do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SET_ACTION_BUTTON

  alias ThistleTea.Game.World.Entity.Player.ActionBar

  defstruct [:button, :packed_data]

  @impl ClientMessage
  def from_binary(payload) do
    <<button::little-size(8), packed_data::little-size(32)>> = payload

    %__MODULE__{
      button: button,
      packed_data: packed_data
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{button: button, packed_data: packed_data}, state),
    do: ActionBar.set_button(state, button, packed_data)
end
