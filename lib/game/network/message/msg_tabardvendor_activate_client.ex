defmodule ThistleTea.Game.Network.Message.MsgTabardvendorActivateClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_TABARDVENDOR_ACTIVATE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:vendor_guid]

  @impl ClientMessage
  def from_binary(<<vendor_guid::little-size(64)>>), do: %__MODULE__{vendor_guid: vendor_guid}

  @impl ClientMessage
  def handle(%__MODULE__{vendor_guid: vendor_guid}, state), do: Guilds.activate_tabard(state, vendor_guid)
end
