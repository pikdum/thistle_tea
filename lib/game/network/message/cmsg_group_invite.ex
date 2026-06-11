defmodule ThistleTea.Game.Network.Message.CmsgGroupInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_INVITE

  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct [:name]

  @impl ClientMessage
  def handle(%__MODULE__{name: name}, %{ready: true, guid: guid, character: character} = state) do
    invitee_guid = Metadata.find_guid_by(:name, name)

    cond do
      invitee_guid == nil or invitee_guid == guid ->
        send_result(name, :bad_player_name)

      not same_team?(character.unit.race, invitee_guid) ->
        send_result(name, :wrong_faction)

      true ->
        invite(state, name, invitee_guid)
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{name: name}
  end

  defp invite(%{guid: guid, character: character}, name, invitee_guid) do
    case PartySystem.invite(guid, character.internal.name, invitee_guid) do
      :ok ->
        Network.send_packet(%Message.SmsgGroupInvite{name: character.internal.name}, invitee_guid)
        send_result(name, :ok)

      {:error, reason} ->
        send_result(name, reason)
    end
  end

  defp same_team?(own_race, invitee_guid) do
    case Metadata.query(invitee_guid, [:race]) do
      %{race: race} when is_integer(race) -> Party.same_team?(own_race, race)
      _ -> false
    end
  end

  defp send_result(name, reason) do
    Network.send_packet(%Result{operation: Result.op_invite(), name: name, result: Result.code(reason)})
  end
end
