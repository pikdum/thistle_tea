defmodule ThistleTea.Game.Network.Message.SmsgPetBroken do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_BROKEN

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
