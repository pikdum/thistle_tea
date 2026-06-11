defmodule ThistleTea.Game.Network.Message.SmsgQuestlogFull do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTLOG_FULL

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
