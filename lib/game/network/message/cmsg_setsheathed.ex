defmodule ThistleTea.Game.Network.Message.CmsgSetsheathed do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SETSHEATHED

  defstruct [:sheath_state]

  @impl ClientMessage
  def from_binary(payload) do
    <<sheath_state::little-size(32)>> = payload

    %__MODULE__{
      sheath_state: sheath_state
    }
  end
end
