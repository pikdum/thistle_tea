defmodule ThistleTea.Game.Network.Message.CmsgGroupAccept do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_ACCEPT

  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.accept(guid, character.internal.name) do
      {:ok, group} -> Notifier.send_group_list(group)
      {:error, _reason} -> :ok
    end

    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
