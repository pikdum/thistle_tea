defmodule ThistleTea.Game.Network.Message.SmsgLootStartRoll do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_START_ROLL

  defstruct [:loot_guid, :slot, :item_id, random_prop: 0, countdown: 60_000]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = msg) do
    <<msg.loot_guid::little-size(64), msg.slot::little-size(32), msg.item_id::little-size(32), 0::little-size(32),
      msg.random_prop::little-size(32), msg.countdown::little-size(32)>>
  end
end
