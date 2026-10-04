defmodule ThistleTea.Game.Inbound.CmsgCompleteCinematic do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_COMPLETE_CINEMATIC

  alias ThistleTea.Game.World.Entity.Player.Cinematic

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Cinematic.finish(state)
end
