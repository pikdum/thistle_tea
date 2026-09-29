defmodule ThistleTea.Game.Network.Message.CmsgSetActionButton do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTION_BUTTON

  defstruct [:button, :packed_data]

  @impl ClientMessage
  def from_binary(payload) do
    <<button::little-size(8), packed_data::little-size(32)>> = payload

    %__MODULE__{
      button: button,
      packed_data: packed_data
    }
  end
end
