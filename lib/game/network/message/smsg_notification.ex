defmodule ThistleTea.Game.Network.Message.SmsgNotification do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_NOTIFICATION

  defstruct [:message]

  @impl ServerMessage
  def to_binary(%__MODULE__{message: message}), do: message <> <<0>>
end
