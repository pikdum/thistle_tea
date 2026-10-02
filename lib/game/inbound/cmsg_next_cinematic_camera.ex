defmodule ThistleTea.Game.Inbound.CmsgNextCinematicCamera do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_NEXT_CINEMATIC_CAMERA

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: state
end
