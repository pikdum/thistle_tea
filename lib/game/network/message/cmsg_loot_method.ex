defmodule ThistleTea.Game.Network.Message.CmsgLootMethod do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_METHOD

  defstruct [:loot_method, :master_looter, :loot_threshold]

  @impl ClientMessage
  def from_binary(payload) do
    <<loot_method::little-size(32), master_looter::little-size(64), loot_threshold::little-size(32)>> = payload

    %__MODULE__{
      loot_method: loot_method,
      master_looter: master_looter,
      loot_threshold: loot_threshold
    }
  end
end
