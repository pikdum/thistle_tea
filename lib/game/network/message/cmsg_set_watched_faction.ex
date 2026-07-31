defmodule ThistleTea.Game.Network.Message.CmsgSetWatchedFaction do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_WATCHED_FACTION

  alias ThistleTea.Game.Player.Reputation

  defstruct [:index]

  @impl ClientMessage
  def handle(%__MODULE__{index: index}, %{ready: true} = state) do
    Reputation.set_watched(state, index)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<index::little-signed-size(32)>>) do
    %__MODULE__{index: index}
  end
end
