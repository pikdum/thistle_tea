defmodule ThistleTea.Game.Network.Message.CmsgRequestPetInfo do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_PET_INFO

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
