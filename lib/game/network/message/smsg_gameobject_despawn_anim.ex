defmodule ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnim do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GAMEOBJECT_DESPAWN_ANIM

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
