defmodule ThistleTea.Game.Inbound.CmsgGroupDisband do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_DISBAND

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Groups.leave(state)
end
