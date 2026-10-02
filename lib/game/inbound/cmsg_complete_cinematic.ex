defmodule ThistleTea.Game.Inbound.CmsgCompleteCinematic do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_COMPLETE_CINEMATIC

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: state
end
