defmodule ThistleTea.Game.Network.Message.MsgLookingForGroup do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_LOOKING_FOR_GROUP

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<0::little-size(32)>>
end
