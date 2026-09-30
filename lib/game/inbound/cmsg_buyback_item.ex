defmodule ThistleTea.Game.Inbound.CmsgBuybackItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BUYBACK_ITEM

  alias ThistleTea.Game.World.Entity.Player.Buyback

  defstruct [:vendor_guid, :slot]

  @impl ClientMessage
  def from_binary(<<vendor::little-size(64), slot::little-size(32)>>), do: %__MODULE__{vendor_guid: vendor, slot: slot}

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Buyback.restore(state, message.vendor_guid, message.slot)
end
