defmodule ThistleTea.Game.Network.Message.CmsgSetFactionInactive do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_FACTION_INACTIVE

  alias ThistleTea.Game.Player.Reputation

  defstruct [:index, :inactive]

  @impl ClientMessage
  def handle(%__MODULE__{index: index, inactive: inactive}, %{ready: true} = state) do
    Reputation.set_inactive(state, index, inactive != 0)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<index::little-size(32), inactive>>) do
    %__MODULE__{index: index, inactive: inactive}
  end
end
