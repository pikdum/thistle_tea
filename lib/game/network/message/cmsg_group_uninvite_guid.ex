defmodule ThistleTea.Game.Network.Message.CmsgGroupUninviteGuid do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_UNINVITE_GUID

  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: target_guid}, %{ready: true, guid: guid} = state) do
    uninvite(guid, target_guid, member_name(guid, target_guid))
    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  def uninvite(remover_guid, target_guid, name) do
    case PartySystem.uninvite(remover_guid, target_guid) do
      {:ok, :invite_cancelled} -> :ok
      {:ok, outcome} -> Notifier.notify_removal(outcome, target_guid, true)
      {:error, reason} -> send_result(name, reason)
    end
  end

  def send_result(name, reason) do
    Network.send_packet(%Result{operation: Result.op_leave(), name: name, result: Result.code(reason)})
  end

  defp member_name(guid, target_guid) do
    with %Party.Group{} = group <- PartySystem.group_of(guid),
         %Party.Member{name: name} <- Party.member(group, target_guid) do
      name
    else
      _ -> ""
    end
  end
end
