defmodule ThistleTea.Game.Network.Message.MsgTabardvendorActivateClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_TABARDVENDOR_ACTIVATE

  alias ThistleTea.Game.Player.Guilds

  defstruct [:vendor_guid]

  @impl ClientMessage
  def from_binary(<<vendor_guid::little-size(64)>>), do: %__MODULE__{vendor_guid: vendor_guid}

  @impl ClientMessage
  def handle(%__MODULE__{vendor_guid: vendor_guid}, state), do: Guilds.activate_tabard(state, vendor_guid)
end

defmodule ThistleTea.Game.Network.Message.MsgTabardvendorActivateServer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_TABARDVENDOR_ACTIVATE

  defstruct [:vendor_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{vendor_guid: vendor_guid}), do: <<vendor_guid::little-size(64)>>
end
