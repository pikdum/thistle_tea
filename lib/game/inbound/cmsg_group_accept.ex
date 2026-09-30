defmodule ThistleTea.Game.Inbound.CmsgGroupAccept do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_ACCEPT

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct []

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Groups.accept(state)
end
