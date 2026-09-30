defmodule ThistleTea.Game.Inbound.CmsgSelfRes do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SELF_RES

  alias ThistleTea.Game.World.Entity.Player.SelfResurrection

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: SelfResurrection.use(state)
end
