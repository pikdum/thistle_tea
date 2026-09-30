defmodule ThistleTea.Game.Inbound.CmsgListInventory do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LIST_INVENTORY

  alias ThistleTea.Game.World.Entity.Player.Vendor

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Vendor.list(state, guid)
end
