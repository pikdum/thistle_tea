defmodule ThistleTea.Game.Network.Message.CmsgLootMethod do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_METHOD

  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:loot_method, :master_looter, :loot_threshold]

  @impl ClientMessage
  def handle(
        %__MODULE__{loot_method: method, master_looter: master_looter, loot_threshold: threshold},
        %{ready: true, guid: guid} = state
      )
      when method in 0..4 and threshold in 0..6 do
    case PartySystem.set_loot(guid, method, master_looter, threshold) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def handle(_message, state), do: state

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
