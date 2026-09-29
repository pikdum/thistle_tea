defmodule ThistleTea.Game.Network.Message.CmsgLootMasterGive do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MASTER_GIVE

  defstruct [:loot_guid, :slot, :target]

  @impl ClientMessage
  def from_binary(payload) do
    <<loot_guid::little-size(64), slot::little-size(8), target::little-size(64)>> = payload

    %__MODULE__{
      loot_guid: loot_guid,
      slot: slot,
      target: target
    }
  end
end
