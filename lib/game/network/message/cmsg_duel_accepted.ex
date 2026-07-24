defmodule ThistleTea.Game.Network.Message.CmsgDuelAccepted do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DUEL_ACCEPTED

  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  defstruct [:player_guid]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, guid: guid} = state) do
    DuelSystem.accept(guid)
    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<player_guid::little-size(64)>>) do
    %__MODULE__{player_guid: player_guid}
  end
end
