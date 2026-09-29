defmodule ThistleTea.Game.Network.Message.CmsgLootRoll do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_ROLL

  defstruct [:guid, :slot, :vote]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), slot::little-size(32), vote::little-size(8)>> = payload

    %__MODULE__{
      guid: guid,
      slot: slot,
      vote: vote
    }
  end
end
