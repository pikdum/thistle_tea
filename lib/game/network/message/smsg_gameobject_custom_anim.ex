defmodule ThistleTea.Game.Network.Message.SmsgGameobjectCustomAnim do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GAMEOBJECT_CUSTOM_ANIM

  defstruct [:guid, animation: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, animation: animation}) do
    <<guid::little-size(64), animation::little-size(32)>>
  end
end
