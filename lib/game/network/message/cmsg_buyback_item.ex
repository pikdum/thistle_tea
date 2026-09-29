defmodule ThistleTea.Game.Network.Message.CmsgBuybackItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUYBACK_ITEM

  defstruct [:vendor_guid, :slot]

  @impl ClientMessage
  def from_binary(<<vendor::little-size(64), slot::little-size(32)>>), do: %__MODULE__{vendor_guid: vendor, slot: slot}
end
