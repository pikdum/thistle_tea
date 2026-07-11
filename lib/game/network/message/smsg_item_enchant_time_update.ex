defmodule ThistleTea.Game.Network.Message.SmsgItemEnchantTimeUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ITEM_ENCHANT_TIME_UPDATE

  defstruct [:item_guid, :slot, :duration_seconds, :player_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.item_guid::little-size(64), message.slot::little-size(32), message.duration_seconds::little-size(32),
      message.player_guid::little-size(64)>>
  end
end
