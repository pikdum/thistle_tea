defmodule ThistleTea.Game.Network.Message.CmsgGroupDisband do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GROUP_DISBAND

  alias ThistleTea.Game.Network.Message.SmsgPartyCommandResult, as: Result
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid, character: character} = state) do
    case PartySystem.leave(guid) do
      {:ok, outcome} ->
        Network.send_packet(%Result{
          operation: Result.op_leave(),
          name: character.internal.name,
          result: Result.code(:ok)
        })

        Notifier.notify_removal(outcome, guid, false)

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
