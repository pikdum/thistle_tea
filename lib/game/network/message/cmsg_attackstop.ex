defmodule ThistleTea.Game.Network.Message.CmsgAttackstop do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSTOP

  alias ThistleTea.Game.Player.Attacking

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Attacking.stop(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
