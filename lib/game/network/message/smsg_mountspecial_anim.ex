defmodule ThistleTea.Game.Network.Message.SmsgMountspecialAnim do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_MOUNTSPECIAL_ANIM

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}), do: <<guid::little-size(64)>>
end
