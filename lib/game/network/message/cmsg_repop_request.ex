defmodule ThistleTea.Game.Network.Message.CmsgRepopRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REPOP_REQUEST

  alias ThistleTea.Game.Player.Corpses

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Corpses.release(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
