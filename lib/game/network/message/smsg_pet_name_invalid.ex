defmodule ThistleTea.Game.Network.Message.SmsgPetNameInvalid do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_NAME_INVALID

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
