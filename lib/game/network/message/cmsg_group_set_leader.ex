defmodule ThistleTea.Game.Network.Message.CmsgGroupSetLeader do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_SET_LEADER

  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: new_leader_guid}, %{ready: true, guid: guid} = state) do
    case PartySystem.set_leader(guid, new_leader_guid) do
      {:ok, group} ->
        Notifier.broadcast(group, %Message.SmsgGroupSetLeader{name: Notifier.leader_name(group)})
        Notifier.send_group_list(group)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end
end
