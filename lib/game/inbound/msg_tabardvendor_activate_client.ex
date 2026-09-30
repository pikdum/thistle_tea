defmodule ThistleTea.Game.Inbound.MsgTabardvendorActivateClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_TABARDVENDOR_ACTIVATE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:vendor_guid]

  @impl ClientMessage
  def from_binary(<<vendor_guid::little-size(64)>>), do: %__MODULE__{vendor_guid: vendor_guid}

  @impl ClientMessage
  def handle(%__MODULE__{vendor_guid: vendor_guid}, state), do: Guilds.activate_tabard(state, vendor_guid)
end
