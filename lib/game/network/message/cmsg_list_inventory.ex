defmodule ThistleTea.Game.Network.Message.CmsgListInventory do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LIST_INVENTORY

  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = c} = state) do
    if !Core.dead?(c) do
      Network.send_packet(%Message.SmsgListInventory{
        vendor_guid: guid,
        items: VendorLoader.items(Guid.entry(guid))
      })
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
