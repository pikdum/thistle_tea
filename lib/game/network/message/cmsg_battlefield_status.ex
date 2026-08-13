defmodule ThistleTea.Game.Network.Message.CmsgBattlefieldStatus do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEFIELD_STATUS

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Battlegrounds.send_status(state)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
