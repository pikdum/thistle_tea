defmodule ThistleTea.Game.Network.Message.SmsgAttackswingBadfacing do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ATTACKSWING_BADFACING

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
