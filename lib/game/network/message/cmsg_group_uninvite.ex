defmodule ThistleTea.Game.Network.Message.CmsgGroupUninvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_UNINVITE

  alias ThistleTea.Game.Network.Message.CmsgGroupUninviteGuid
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, %{ready: true, guid: guid} = state) do
    case resolve_guid(guid, name) do
      nil -> CmsgGroupUninviteGuid.send_result(name, :target_not_in_group)
      target_guid -> CmsgGroupUninviteGuid.uninvite(guid, target_guid, name)
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  defp resolve_guid(guid, name) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{guid: target_guid} <- Party.member_by_name(group, name) do
      target_guid
    else
      _ -> Metadata.find_guid_by(:name, name)
    end
  end
end
