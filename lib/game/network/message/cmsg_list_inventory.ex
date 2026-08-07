defmodule ThistleTea.Game.Network.Message.CmsgListInventory do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LIST_INVENTORY

  alias ThistleTea.Game.Player.Vendor

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Vendor.list(state, guid)

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
