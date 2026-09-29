defmodule ThistleTea.Game.Network.Message.MsgTabardvendorActivateClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_TABARDVENDOR_ACTIVATE

  defstruct [:vendor_guid]

  @impl ClientMessage
  def from_binary(<<vendor_guid::little-size(64)>>), do: %__MODULE__{vendor_guid: vendor_guid}
end
