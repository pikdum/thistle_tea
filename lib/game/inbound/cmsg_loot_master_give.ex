defmodule ThistleTea.Game.Inbound.CmsgLootMasterGive do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT_MASTER_GIVE

  alias ThistleTea.Game.World.Entity.Player.Looting

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

  @impl ClientMessage
  def handle(
        %__MODULE__{loot_guid: loot_guid, slot: slot, target: target},
        %{ready: true, loot_guid: loot_guid} = state
      ) do
    Looting.master_give(state, loot_guid, slot, target)
  end

  def handle(%__MODULE__{}, state), do: state
end
