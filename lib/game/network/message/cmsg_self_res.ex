defmodule ThistleTea.Game.Network.Message.CmsgSelfRes do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SELF_RES

  alias ThistleTea.Game.Player.SelfResurrection

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: SelfResurrection.use(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
