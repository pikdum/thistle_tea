defmodule ThistleTea.Game.Inbound.CmsgGroupDecline do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_DECLINE

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Groups.decline(state)
end
