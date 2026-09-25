defmodule ThistleTea.Game.Network.Message.SmsgGameobjectResetState do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GAMEOBJECT_RESET_STATE

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
