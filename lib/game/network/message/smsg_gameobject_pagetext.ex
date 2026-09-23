defmodule ThistleTea.Game.Network.Message.SmsgGameobjectPagetext do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GAMEOBJECT_PAGETEXT

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
