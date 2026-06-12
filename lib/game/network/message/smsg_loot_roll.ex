defmodule ThistleTea.Game.Network.Message.SmsgLootRoll do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_ROLL

  defstruct [:loot_guid, :slot, :player_guid, :item_id, :roll_number, :roll_type, random_prop: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    <<msg.loot_guid::little-size(64), msg.slot::little-size(32), msg.player_guid::little-size(64),
      msg.item_id::little-size(32), 0::little-size(32), msg.random_prop::little-size(32),
      msg.roll_number::little-size(8), msg.roll_type::little-size(8)>>
  end
end
