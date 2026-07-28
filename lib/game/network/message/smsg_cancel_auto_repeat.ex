defmodule ThistleTea.Game.Network.Message.SmsgCancelAutoRepeat do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CANCEL_AUTO_REPEAT

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
