defmodule ThistleTea.Game.Network.Message.CmsgGroupDecline do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_DECLINE

  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.decline(guid) do
      {:ok, inviter_guid} ->
        Network.send_packet(%Message.SmsgGroupDecline{name: character.internal.name}, inviter_guid)

      {:error, _reason} ->
        :ok
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
