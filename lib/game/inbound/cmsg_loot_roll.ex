defmodule ThistleTea.Game.Inbound.CmsgLootRoll do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT_ROLL

  alias ThistleTea.Game.World.Entity

  @votes %{0 => :pass, 1 => :need, 2 => :greed}

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

  @impl ClientMessage
  def handle(%__MODULE__{guid: loot_guid, slot: slot, vote: vote}, %{ready: true, guid: guid} = state) do
    case Map.fetch(@votes, vote) do
      {:ok, vote} -> Entity.loot_roll_vote(loot_guid, guid, slot, vote)
      :error -> :ok
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state
end
