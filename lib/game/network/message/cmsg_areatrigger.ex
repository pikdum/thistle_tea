defmodule ThistleTea.Game.Network.Message.CmsgAreatrigger do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AREATRIGGER

  defstruct [:trigger_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<trigger_id::little-size(32)>> = payload

    %__MODULE__{
      trigger_id: trigger_id
    }
  end
end
