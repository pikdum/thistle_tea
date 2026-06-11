defmodule ThistleTea.Game.Network.Message.CmsgRequestPartyMemberStats do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_PARTY_MEMBER_STATS

  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.MemberStats
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: target_guid}, %{ready: true, guid: guid} = state) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{} <- Party.member(group, target_guid) do
      send_stats(guid, target_guid)
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  defp send_stats(requester_guid, target_guid) do
    case EntityRegistry.whereis(target_guid) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:request_party_stats, requester_guid})

      _ ->
        Network.send_packet(struct(Message.SmsgPartyMemberStatsFull, MemberStats.offline(target_guid)))
    end
  end
end
