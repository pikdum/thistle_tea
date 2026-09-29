defmodule ThistleTea.Game.Network.Message.MsgTabardvendorActivate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_TABARDVENDOR_ACTIVATE

  defstruct [:vendor_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{vendor_guid: vendor_guid}), do: <<vendor_guid::little-size(64)>>
end
