defmodule ThistleTea.Game.Inbound.CmsgLootMethod do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT_METHOD

  alias ThistleTea.Game.World.Entity.Player.Groups

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

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state),
    do: Groups.set_loot(state, message.loot_method, message.master_looter, message.loot_threshold)
end
